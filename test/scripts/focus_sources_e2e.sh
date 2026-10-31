#!/usr/bin/env bash
# End-to-end check of the Wayland focus sources (V1 Wayland): starts a real
# compositor nested and headless, with its own D-Bus session and runtime
# directory, opens a GTK 4 probe (native Wayland) and then a GTK 3 probe
# (XWayland), and lets compositor_focus_e2e_test.dart ask the source the app
# picks from that environment which window has focus.
#
# Usage: focus_sources_e2e.sh [sway|kwin]...   (default: every one installed)
# Under sway the probe is also asked through the wlr toplevel protocol.
# Manual check, not in CI: needs sway and/or kwin_wayland, Xwayland,
# python3-gi with GTK 3 and 4, and flutter. Sends no input anywhere and
# never touches the running desktop session.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PROBE="$ROOT/test/scripts/focus_probe_window.py"
TEST="test/services/desktop_paste/focused_target/compositor_focus_e2e_test.dart"
APP_ID=de.whispaste.FocusProbe
X11_NAME=whispaste-x11-probe
X11_CLASS=Focus_probe_window.py # GTK 3 derives it from the script name

targets=("$@")
if [ ${#targets[@]} -eq 0 ]; then
  command -v sway >/dev/null && targets+=(sway)
  command -v kwin_wayland >/dev/null && targets+=(kwin)
fi
[ ${#targets[@]} -gt 0 ] || { echo "no compositor installed" >&2; exit 2; }

# Wayland socket paths are limited to 108 bytes, so keep the runtime dir short.
RT="$(mktemp -d "/run/user/$(id -u)/wpf.XXXXXX")"
chmod 700 "$RT"
trap 'rm -rf "$RT"' EXIT

# Runs inside the compositor's session: open a probe, wait until it maps,
# run the Dart check against it. $1 = desktop name, $2 = toolkit,
# $3 = expected identifier.
cat >"$RT/check.sh" <<'CHECK'
set -u
desktop="$1"; toolkit="$2"; expect="$3"
if [ "$toolkit" = gtk3 ]; then
  GDK_BACKEND=x11 python3 "$PROBE" gtk3 "$X11_NAME" 40 >>"$RT/probe.log" 2>&1 &
else
  GDK_BACKEND=wayland python3 "$PROBE" gtk4 "$APP_ID" 40 >>"$RT/probe.log" 2>&1 &
fi
sleep 3
cd "$ROOT"
WP_FOCUS_E2E_DESKTOP="$desktop" WP_FOCUS_E2E_EXPECT="$expect" \
  flutter test --tags compositor-e2e "$TEST" >"$RT/test-$desktop-$toolkit.log" 2>&1
echo "$desktop $toolkit rc=$?" >>"$RT/results"
grep -h FOCUS_E2E "$RT/test-$desktop-$toolkit.log" >>"$RT/results" || true
if [ "$desktop" = sway ]; then
  # The same probe through the wlr toplevel protocol (Flatpak fallback).
  # The protocol carries one name: for XWayland windows the WM_CLASS class.
  wlr_expect="$expect"
  [ "$toolkit" = gtk3 ] && wlr_expect="$X11_CLASS"
  WP_FOCUS_E2E_WLR=1 WP_FOCUS_E2E_DESKTOP="$desktop" WP_FOCUS_E2E_EXPECT="$wlr_expect" \
    flutter test --tags compositor-e2e "$TEST" >"$RT/test-wlr-$toolkit.log" 2>&1
  echo "wlr $toolkit rc=$?" >>"$RT/results"
  grep -h FOCUS_E2E "$RT/test-wlr-$toolkit.log" >>"$RT/results" || true
fi
CHECK

cat >"$RT/session.sh" <<'SESSION'
set -u
desktop="$1"
bash "$RT/check.sh" "$desktop" gtk4 "$APP_ID"
bash "$RT/check.sh" "$desktop" gtk3 "$X11_NAME"
echo done >"$RT/finished-$desktop"
SESSION

export ROOT PROBE TEST APP_ID X11_NAME X11_CLASS RT
L="$HOME/.cache/whispaste-flutter.lock"
until (set -C; echo "focus-e2e-$$" >"$L") 2>/dev/null; do sleep 5; done
# shellcheck disable=SC2329  # called by the EXIT trap
release() { grep -qx "focus-e2e-$$" "$L" 2>/dev/null && rm -f "$L"; rm -rf "$RT"; }
trap release EXIT

for target in "${targets[@]}"; do
  case "$target" in
    sway)
      printf 'xwayland enable\nexec bash %s/session.sh sway && swaymsg exit\n' \
        "$RT" >"$RT/sway.conf"
      env -u DISPLAY -u WAYLAND_DISPLAY -u SWAYSOCK XDG_RUNTIME_DIR="$RT" \
        XDG_SESSION_TYPE=wayland XDG_CURRENT_DESKTOP=sway \
        WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1 \
        timeout 300 dbus-run-session -- sway -c "$RT/sway.conf" \
        >"$RT/sway.log" 2>&1 || true
      ;;
    kwin)
      env -u DISPLAY -u WAYLAND_DISPLAY XDG_RUNTIME_DIR="$RT" \
        XDG_SESSION_TYPE=wayland XDG_CURRENT_DESKTOP=KDE \
        KWIN_COMPOSE=Q QT_QPA_PLATFORM=wayland \
        timeout 300 dbus-run-session -- kwin_wayland --virtual --xwayland \
        --socket wpf-kwin --width 1280 --height 720 \
        --exit-with-session "bash $RT/session.sh kde" \
        >"$RT/kwin.log" 2>&1 || true
      ;;
    *) echo "unknown compositor: $target" >&2; exit 2 ;;
  esac
done

echo "focus_sources_e2e results:"
sed 's/^/  /' "$RT/results" 2>/dev/null || echo "  (none)"
status=0
for target in "${targets[@]}"; do
  desktop=$([ "$target" = kwin ] && echo kde || echo "$target")
  checks=("$desktop")
  [ "$desktop" = sway ] && checks+=(wlr)
  for check in "${checks[@]}"; do
    for toolkit in gtk4 gtk3; do
      if ! grep -qx "$check $toolkit rc=0" "$RT/results" 2>/dev/null; then
        echo "FAIL: $check $toolkit"
        tail -20 "$RT/test-$check-$toolkit.log" 2>/dev/null | sed 's/^/    /'
        status=1
      fi
    done
  done
done
[ $status -eq 0 ] && echo "focus_sources_e2e: every compositor reported the probe"
exit $status
