#!/usr/bin/env bash
# Compiles and runs the Linux X error trap runtime test
# (linux/runner/x11_window_test.cc) on a private Xvfb display: reading a
# closed window must not end the process (XP-7-18). Needs libgtk-3-dev and
# xvfb (Linux only; CI Linux job).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
# shellcheck disable=SC2046  # pkg-config prints separate flags on purpose
"${CXX:-c++}" -std=c++17 -Wall -Wextra -Werror -I "$ROOT/linux/runner" \
  "$ROOT/linux/runner/x11_window.cc" \
  "$ROOT/linux/runner/x11_window_test.cc" \
  $(pkg-config --cflags --libs gtk+-3.0 x11) -o "$OUT/x11_window_test"
# GDK_BACKEND=x11: the test always runs on the private X display.
env -u WAYLAND_DISPLAY GDK_BACKEND=x11 \
  timeout 60 xvfb-run -a "$OUT/x11_window_test"
