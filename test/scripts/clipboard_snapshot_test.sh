#!/usr/bin/env bash
# Compiles and runs the Linux full clipboard snapshot runtime test
# (linux/runner/clipboard_snapshot_test.cc) on a private Xvfb display: a second
# process owns image, HTML and text, WhisPaste snapshots, pastes and restores
# them (P1.1). Needs libgtk-3-dev and xvfb (Linux only; CI Linux job).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
# shellcheck disable=SC2046  # pkg-config prints separate flags on purpose
"${CXX:-c++}" -std=c++17 -Wall -Wextra -Werror -I "$ROOT/linux/runner" \
  "$ROOT/linux/runner/clipboard_hint.cc" \
  "$ROOT/linux/runner/clipboard_receipt.cc" \
  "$ROOT/linux/runner/clipboard_snapshot.cc" \
  "$ROOT/linux/runner/clipboard_snapshot_test.cc" \
  $(pkg-config --cflags --libs gtk+-3.0) -o "$OUT/clipboard_snapshot_test"
# GDK_BACKEND=x11: the test always runs on the private X display.
env -u WAYLAND_DISPLAY GDK_BACKEND=x11 \
  timeout 60 xvfb-run -a "$OUT/clipboard_snapshot_test"
