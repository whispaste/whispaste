#!/usr/bin/env bash
# Compiles and runs the Linux clipboard read receipt runtime test
# (linux/runner/clipboard_receipt_test.cc) on a private Xvfb display: a second
# process reads like a monitor, Klipper and the paste target, then takes the
# clipboard over (GR-015). Needs libgtk-3-dev and xvfb (Linux only; CI Linux job).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
# shellcheck disable=SC2046  # pkg-config prints separate flags on purpose
"${CXX:-c++}" -std=c++17 -Wall -Wextra -Werror -I "$ROOT/linux/runner" \
  "$ROOT/linux/runner/clipboard_hint.cc" \
  "$ROOT/linux/runner/clipboard_receipt.cc" \
  "$ROOT/linux/runner/clipboard_receipt_test.cc" \
  $(pkg-config --cflags --libs gtk+-3.0) -o "$OUT/clipboard_receipt_test"
# GDK_BACKEND=x11: the test always runs on the private X display.
env -u WAYLAND_DISPLAY GDK_BACKEND=x11 \
  timeout 60 xvfb-run -a "$OUT/clipboard_receipt_test"
