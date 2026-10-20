#!/usr/bin/env bash
# Compiles and runs the Linux hotkey runtime test of the vendored
# hotkey_manager_linux (packages/hotkey_manager_linux/linux/runtime_test) on a
# private Xvfb display: Ctrl+Shift+D must fire through keybinder plainly, with
# NumLock, with CapsLock and after a layout switch. A second run with
# keybinder's default (cooked) matching must fail, so the test is known to
# catch the bug. Needs libgtk-3-dev, libkeybinder-3.0-dev, libxtst-dev, xvfb
# and setxkbmap (Linux only; CI Linux job).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SRC="$ROOT/packages/hotkey_manager_linux/linux"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
# shellcheck disable=SC2046  # pkg-config prints separate flags on purpose
"${CXX:-c++}" -std=c++17 -Wall -Wextra -Werror \
  "$SRC/keybinder_raw.cc" "$SRC/flutter_keyval.cc" \
  "$SRC/runtime_test/keybinder_raw_test.cc" \
  $(pkg-config --cflags --libs gtk+-3.0 keybinder-3.0 x11 xtst) \
  -o "$OUT/keybinder_raw_test"
run() {
  # GDK_BACKEND=x11: keybinder only works on X11; the test owns its display.
  env -u WAYLAND_DISPLAY GDK_BACKEND=x11 \
    timeout 60 xvfb-run -a "$OUT/keybinder_raw_test" "$@"
}
echo "raw matching (the app's mode):"
run
echo "keybinder default, must fail:"
if run --cooked; then
  echo "FAIL: the cooked control run passed, the test no longer catches the bug"
  exit 1
fi
echo "keybinder_raw_test: OK"
