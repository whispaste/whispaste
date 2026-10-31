#!/usr/bin/env bash
# Latency benchmark: old plain-text clipboard read (VORHER) against the full
# clipboard snapshot and restore (NACHHER), P1.1. Compiles and runs
# clipboard_snapshot_bench.cc on a private Xvfb display; see README.md here.
# Usage: clipboard_snapshot_bench.sh [iterations]   (default 30)
# Needs libgtk-3-dev and xvfb (Linux only). Measures only; asserts nothing.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
REV="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
echo "revision: $REV  host: $(uname -srm)"
# shellcheck disable=SC2046  # pkg-config prints separate flags on purpose
"${CXX:-c++}" -std=c++17 -O2 -Wall -Wextra -Werror -I "$ROOT/linux/runner" \
  "$ROOT/linux/runner/clipboard_hint.cc" \
  "$ROOT/linux/runner/clipboard_receipt.cc" \
  "$ROOT/linux/runner/clipboard_snapshot.cc" \
  "$HERE/clipboard_snapshot_bench.cc" \
  $(pkg-config --cflags --libs gtk+-3.0) -o "$OUT/clipboard_snapshot_bench"
# GDK_BACKEND=x11: the benchmark always runs on the private X display.
env -u WAYLAND_DISPLAY GDK_BACKEND=x11 \
  timeout 900 xvfb-run -a "$OUT/clipboard_snapshot_bench" "${1:-30}"
