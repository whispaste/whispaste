#!/usr/bin/env bash
#
# gnome_extension_e2e.sh - end-to-end check of the WhisPaste Focus GNOME Shell
# extension in a nested, headless GNOME Shell on a private D-Bus session.
#
# Local run only, not a CI gate. Needs gnome-shell, dbus-run-session, gsettings,
# gdbus and python3 with GTK 4 bindings. It never touches the real session: it
# uses its own session bus, its own HOME and XDG_* under a private runtime dir,
# and it ends only the processes it started itself, by PID.
#
# Usage: bash test/scripts/gnome_extension_e2e.sh [repo_root]
set -euo pipefail

UUID="whispaste-focus@whispaste.de"
BUS_NAME="de.whispaste.ShellFocus"
OBJ_PATH="/de/whispaste/ShellFocus"
IFACE="de.whispaste.ShellFocus1"
WL_NAME="wpg-e2e"
GTK_APP_ID="de.whispaste.e2e-probe"
X11_INSTANCE="whispaste-x11-probe"
SECRET_TITLE="WPG-SECRET-TITLE-7f3a"
LATENCY_RUNS=20

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
EXT_SRC="$ROOT/packaging/linux/gnome-shell-extension/$UUID"

# Re-run inside a private session bus, so neither the shell nor the clients
# can reach the real desktop session.
if [[ "${WP_GNOME_E2E_INNER:-0}" != 1 ]]; then
  for tool in dbus-run-session gnome-shell gsettings gdbus python3 ps; do
    command -v "$tool" >/dev/null || { echo "missing tool: $tool" >&2; exit 2; }
  done
  exec env WP_GNOME_E2E_INNER=1 dbus-run-session -- bash "${BASH_SOURCE[0]}" "$ROOT"
fi

fail() {
  echo "FAIL: $*" >&2
  if [[ -n "${RUN:-}" && -f "$RUN/shell.log" ]]; then
    echo "--- gnome-shell log (tail) ---" >&2
    tail -n 30 "$RUN/shell.log" >&2 || true
  fi
  exit 1
}

pass() { echo "PASS: $*"; }

# All descendants of PID $1, deepest first.
descendants() {
  local kid
  for kid in $(ps -o pid= --ppid "$1" 2>/dev/null); do
    descendants "$kid"
    echo "$kid"
  done
}

CLIENT_PIDS=()
SHELL_PID=""

cleanup() {
  local rc=$? pid
  local -a victims=()
  if [[ $rc -ne 0 && -n "${RUN:-}" && -f "$RUN/shell.log" ]]; then
    echo "--- gnome-shell log (tail, exit $rc) ---" >&2
    grep -vE 'dbus-daemon|Activating|Successfully' "$RUN/shell.log" | tail -n 40 >&2 || true
  fi
  # Bus daemon: the child of dbus-run-session (our parent) named dbus-daemon.
  local bus_pid
  bus_pid="$(ps -o pid= --ppid "$PPID" -C dbus-daemon 2>/dev/null | head -n1 | tr -d ' ' || true)"
  for pid in ${bus_pid:-} ${SHELL_PID:-}; do
    [[ -n "$pid" ]] || continue
    victims+=("$pid")
    while read -r kid; do victims+=("$kid"); done < <(descendants "$pid")
  done
  for pid in ${CLIENT_PIDS[@]+"${CLIENT_PIDS[@]}"}; do
    victims+=("$pid")
  done
  for pid in ${victims[@]+"${victims[@]}"}; do
    kill -TERM "$pid" 2>/dev/null || true
  done
  sleep 3
  for pid in ${victims[@]+"${victims[@]}"}; do
    if kill -0 "$pid" 2>/dev/null; then kill -KILL "$pid" 2>/dev/null || true; fi
  done
  if [[ -n "${RUN:-}" && "$RUN" == /run/user/*/wpg.* ]]; then
    rm -rf -- "$RUN"
  fi
  exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

[[ -d "$EXT_SRC" ]] || fail "extension source not found: $EXT_SRC"
RUNBASE="/run/user/$(id -u)"
[[ -d "$RUNBASE" ]] || fail "no $RUNBASE runtime dir"
RUN="$(mktemp -d "$RUNBASE/wpg.XXXXXX")"
chmod 700 "$RUN"

# The Dart step (1b) needs the real home for flutter and its lock.
REAL_HOME="$HOME"
export HOME="$RUN/home"
export XDG_RUNTIME_DIR="$RUN"
export XDG_CONFIG_HOME="$RUN/config"
export XDG_DATA_HOME="$RUN/data"
export XDG_CACHE_HOME="$RUN/cache"
export XDG_STATE_HOME="$RUN/state"
export XDG_CURRENT_DESKTOP=GNOME
export XDG_SESSION_TYPE=wayland
export GSETTINGS_BACKEND=keyfile
unset DISPLAY WAYLAND_DISPLAY

mkdir -p "$HOME" "$XDG_CONFIG_HOME/glib-2.0/settings" \
  "$XDG_DATA_HOME/gnome-shell/extensions" "$XDG_CACHE_HOME" "$XDG_STATE_HOME"

# Install the extension into this HOME and enable it through gsettings.
cp -r "$EXT_SRC" "$XDG_DATA_HOME/gnome-shell/extensions/$UUID"
gsettings set org.gnome.shell enabled-extensions "['$UUID']"
gsettings set org.gnome.shell disable-user-extensions false

# Headless nested shell with one virtual monitor. XWayland comes up with it,
# unless WP_E2E_NO_X11=1 (then only the Wayland checks run; see the X11 step).
SHELL_ARGS=(--headless --wayland --virtual-monitor 1280x720 --wayland-display "$WL_NAME")
if [[ "${WP_E2E_NO_X11:-0}" == 1 ]]; then
  SHELL_ARGS+=(--no-x11)
fi
gnome-shell "${SHELL_ARGS[@]}" >"$RUN/shell.log" 2>&1 &
SHELL_PID=$!

name_has_owner() {
  gdbus call --session --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus \
    --method org.freedesktop.DBus.NameHasOwner "$1" 2>/dev/null | grep -qF "(true,)"
}

wait_for_name() { # <bus name> <timeout seconds>
  local i
  for ((i = 0; i < $2 * 2; i++)); do
    name_has_owner "$1" && return 0
    kill -0 "$SHELL_PID" 2>/dev/null || return 1
    sleep 0.5
  done
  return 1
}

START_NS="$(date +%s%N)"
wait_for_name org.gnome.Shell 90 || fail "gnome-shell did not claim org.gnome.Shell"
echo "gnome-shell ready after $(( ($(date +%s%N) - START_NS) / 1000000 )) ms"
wait_for_name "$BUS_NAME" 30 || fail "extension did not claim $BUS_NAME (not enabled or enable() failed)"
pass "extension owns $BUS_NAME"

focus_call() {
  gdbus call --session --timeout 10 --dest "$BUS_NAME" --object-path "$OBJ_PATH" \
    --method "$IFACE.GetFocusedWindow" 2>&1 || true
}

# Polls GetFocusedWindow until its output contains the fixed string $1.
wait_for_focus() { # <fixed string> <timeout seconds>
  local i out=""
  for ((i = 0; i < $2 * 2; i++)); do
    out="$(focus_call)"
    if grep -qF -- "$1" <<<"$out"; then LAST_FOCUS="$out"; return 0; fi
    sleep 0.5
  done
  LAST_FOCUS="$out"
  return 1
}

expect_in_focus() { # <fixed string> <message>
  grep -qF -- "$1" <<<"$LAST_FOCUS" || fail "$2 (got: $LAST_FOCUS)"
}

# Protocol version property.
VERSION_OUT="$(gdbus call --session --timeout 10 --dest "$BUS_NAME" --object-path "$OBJ_PATH" \
  --method org.freedesktop.DBus.Properties.Get "$IFACE" Version 2>&1 || true)"
grep -qF "(<uint32 1>,)" <<<"$VERSION_OUT" || fail "Version property is not 1 (got: $VERSION_OUT)"
pass "Version property = 1"

# ── 1. Wayland GTK4 client with an application ID ──────────────────────────
cat >"$RUN/wayland-client.py" <<'PYEOF'
import sys

import gi

gi.require_version("Gtk", "4.0")
from gi.repository import Gtk  # noqa: E402

app = Gtk.Application(application_id=sys.argv[1])


def on_activate(application):
    window = Gtk.ApplicationWindow(application=application, title=sys.argv[2])
    window.set_default_size(320, 200)
    window.present()


app.connect("activate", on_activate)
app.run([sys.argv[0]])
PYEOF

WAYLAND_DISPLAY="$WL_NAME" GDK_BACKEND=wayland \
  python3 "$RUN/wayland-client.py" "$GTK_APP_ID" "$SECRET_TITLE" >"$RUN/wayland-client.log" 2>&1 &
WAYLAND_PID=$!
CLIENT_PIDS+=("$WAYLAND_PID")

if ! wait_for_focus "'app_id': <'$GTK_APP_ID'>" 20; then
  echo "diagnostic: windows as the shell sees them:" >&2
  gdbus call --session --timeout 5 --dest org.gnome.Shell \
    --object-path /org/gnome/Shell/Introspect \
    --method org.gnome.Shell.Introspect.GetWindows >&2 || true
  fail "focused window does not report app_id $GTK_APP_ID (got: $LAST_FOCUS)"
fi
expect_in_focus "'client_type': <'wayland'>" "Wayland client_type missing"
if grep -qF -- "$SECRET_TITLE" <<<"$LAST_FOCUS"; then
  fail "window title leaked into GetFocusedWindow"
fi
pass "Wayland GTK client: app_id=$GTK_APP_ID, client_type=wayland, no title"

# ── 1b. Optional: the app's Dart source against the same extension ─────────
# WP_GNOME_E2E_DART=1 runs compositor_focus_e2e_test.dart here, so the
# GnomeShellFocusSource and the settings status probe are checked too.
if [ "${WP_GNOME_E2E_DART:-0}" = 1 ]; then
  LOCK="$REAL_HOME/.cache/whispaste-flutter.lock"
  until (set -C; echo "gnome-e2e-$$" >"$LOCK") 2>/dev/null; do sleep 5; done
  DART_RC=0
  (cd "$ROOT" && HOME="$REAL_HOME" WAYLAND_DISPLAY="$WL_NAME" XDG_SESSION_TYPE=wayland \
    XDG_CURRENT_DESKTOP=GNOME WP_FOCUS_E2E_DESKTOP=gnome \
    WP_FOCUS_E2E_EXPECT="$GTK_APP_ID" flutter test --tags compositor-e2e \
    test/services/desktop_paste/focused_target/compositor_focus_e2e_test.dart) \
    >"$RUN/dart-e2e.log" 2>&1 || DART_RC=$?
  grep -qx "gnome-e2e-$$" "$LOCK" 2>/dev/null && rm -f "$LOCK"
  grep -h FOCUS_E2E "$RUN/dart-e2e.log" || true
  [ "$DART_RC" -eq 0 ] || { tail -20 "$RUN/dart-e2e.log" >&2; fail "Dart GNOME source did not report $GTK_APP_ID"; }
  pass "Dart GnomeShellFocusSource: $GTK_APP_ID, status available"
fi

# ── 2. Latency of the call, with the Wayland client focused ────────────────
TIMES=()
for ((i = 0; i < LATENCY_RUNS; i++)); do
  T0="$(date +%s%N)"
  focus_call >/dev/null
  TIMES+=($(( ($(date +%s%N) - T0) / 1000 )))
done
SORTED=$(printf '%s\n' "${TIMES[@]}" | sort -n)
MEDIAN_US=$(sed -n "$(( (LATENCY_RUNS + 1) / 2 ))p" <<<"$SORTED")
MAX_US=$(tail -n1 <<<"$SORTED")
echo "gdbus GetFocusedWindow latency over $LATENCY_RUNS calls: median $(( MEDIAN_US / 1000 )) ms, max $(( MAX_US / 1000 )) ms (includes gdbus process start)"

# Stop the Wayland client; with no window focused the answer is an empty dict.
kill -TERM "$WAYLAND_PID" 2>/dev/null || true
wait "$WAYLAND_PID" 2>/dev/null || true
wait_for_focus "@a{sv} {}," 20 || fail "no focused window should give an empty dict (got: $LAST_FOCUS)"
pass "no focus -> empty dict"

# ── 3. X11 client through XWayland, without an application ID ─────────────
if [[ "${WP_E2E_NO_X11:-0}" == 1 ]]; then
  echo "SKIP: X11 check (WP_E2E_NO_X11=1, shell started with --no-x11)"
else
X_DISPLAY="$(grep -oE 'public X11 display :[0-9]+' "$RUN/shell.log" | grep -oE ':[0-9]+' | head -n1 || true)"
[[ -n "$X_DISPLAY" ]] || fail "shell did not report an XWayland display (see $RUN/shell.log)"

cat >"$RUN/x11-client.py" <<'PYEOF'
import gi

gi.require_version("Gtk", "4.0")
from gi.repository import GLib, Gtk  # noqa: E402

GLib.set_prgname("whispaste-x11-probe")
GLib.set_application_name("WhisPaste X11 Probe")
window = Gtk.Window(title="x11 probe")
window.set_default_size(320, 200)
window.present()
GLib.MainLoop().run()
PYEOF

env -u WAYLAND_DISPLAY DISPLAY="$X_DISPLAY" GDK_BACKEND=x11 \
  python3 "$RUN/x11-client.py" >"$RUN/x11-client.log" 2>&1 &
X11_PID=$!
CLIENT_PIDS+=("$X11_PID")

wait_for_focus "'client_type': <'x11'>" 20 \
  || fail "X11 client is not reported as client_type x11 (got: $LAST_FOCUS)"
expect_in_focus "'wm_class_instance': <'$X11_INSTANCE'>" "X11 wm_class_instance missing"
if grep -qF "'app_id'" <<<"$LAST_FOCUS"; then
  fail "X11 client without application ID must not report app_id (got: $LAST_FOCUS)"
fi
pass "X11 client via XWayland ($X_DISPLAY): wm_class_instance=$X11_INSTANCE, client_type=x11"

kill -TERM "$X11_PID" 2>/dev/null || true
wait "$X11_PID" 2>/dev/null || true
fi

echo "E2E run finished."
