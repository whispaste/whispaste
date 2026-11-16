#!/usr/bin/env bash
# Wayland counterpart of klipper_hint_e2e.sh (PAR-012): a headless nested
# kwin_wayland with Xwayland, its own D-Bus session and XDG folders, and
# Klipper as a native Wayland client. The texts go through Xwayland, the
# path the app takes on a Plasma Wayland desktop (main.cc forces
# GDK_BACKEND=x11), so KWin's Xwayland clipboard bridge has to carry the
# x-kde-passwordManagerHint over to Klipper. Passes when Klipper kept the
# plain texts and skipped the hinted one.
#
# Native Wayland GTK clients are not covered: KWin accepts a selection only
# from the client with keyboard focus, and a headless session has none.
#
# Manual check, not in CI: needs kwin-wayland, plasma-workspace
# (plasmawindowed, qdbus6), Xwayland and libgtk-3-dev. Never touches the
# running desktop session; no input devices are used.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
for tool in kwin_wayland Xwayland plasmawindowed qdbus6 dbus-run-session; do
  command -v "$tool" >/dev/null || { echo "missing: $tool" >&2; exit 2; }
done
OUT="$(mktemp -d)"
# The Wayland socket path must stay under 108 bytes, so the runtime folder
# is a short one next to the user's own.
RUNTIME="$(mktemp -d "/run/user/$(id -u)/wpk.XXXXXX")"
trap 'rm -rf "$OUT" "$RUNTIME"' EXIT
# shellcheck disable=SC2046  # pkg-config prints separate flags on purpose
"${CXX:-c++}" -std=c++17 -Wall -Wextra -Werror -I "$ROOT/linux/runner" \
  "$ROOT/linux/runner/clipboard_hint.cc" \
  "$ROOT/linux/runner/clipboard_hint_hold.cc" \
  $(pkg-config --cflags --libs gtk+-3.0) -o "$OUT/hold"

cat >"$OUT/inner.sh" <<'INNER'
set -u
OUT="$1"
# kwin_wayland hands its Xwayland display to the session in DISPLAY.
XDISPLAY="${DISPLAY:-}"
export XDG_CONFIG_HOME="$OUT/config" XDG_DATA_HOME="$OUT/data" \
  XDG_CACHE_HOME="$OUT/cache" XDG_STATE_HOME="$OUT/state"
QT_QPA_PLATFORM=wayland DISPLAY='' \
  plasmawindowed org.kde.plasma.clipboard >"$OUT/klipper.log" 2>&1 &
klipper=$!
for _ in $(seq 1 40); do
  qdbus6 org.kde.klipper /klipper >/dev/null 2>&1 && break
  sleep 0.5
done
export GDK_BACKEND=x11 DISPLAY="$XDISPLAY"
"$OUT/hold" plain "whispaste-plain-before"; sleep 2
"$OUT/hold" hint "whispaste-hinted"; sleep 2
"$OUT/hold" plain "whispaste-plain-after"; sleep 2
for i in 0 1 2 3; do
  qdbus6 org.kde.klipper /klipper \
    org.kde.klipper.klipper.getClipboardHistoryItem "$i" 2>/dev/null || true
done >"$OUT/history.txt"
kill "$klipper" 2>/dev/null || true
wait "$klipper" 2>/dev/null || true
INNER

touch "$OUT/history.txt"
XDG_RUNTIME_DIR="$RUNTIME" timeout 150 dbus-run-session -- \
  env -u DISPLAY -u WAYLAND_DISPLAY \
  kwin_wayland --virtual --xwayland --socket wp-klipper \
  --exit-with-session "bash $OUT/inner.sh $OUT" >/dev/null 2>&1 || true

echo "Klipper history:"
sed 's/^/  /' "$OUT/history.txt"
grep -qx "whispaste-plain-before" "$OUT/history.txt" ||
  { echo "FAIL: Klipper did not record the plain control (not running?)"; exit 1; }
grep -qx "whispaste-plain-after" "$OUT/history.txt" ||
  { echo "FAIL: Klipper did not record the second plain control"; exit 1; }
if grep -qx "whispaste-hinted" "$OUT/history.txt"; then
  echo "FAIL: Klipper recorded the hinted text"
  exit 1
fi
echo "klipper_hint_wayland_e2e: Klipper skipped the hinted text on Wayland"
