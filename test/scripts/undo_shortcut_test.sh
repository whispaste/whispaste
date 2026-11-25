#!/usr/bin/env bash
# Compiles and runs the Linux undo shortcut decision test
# (linux/runner/undo_shortcut_test.cc, #2078). Platform-neutral C++17, so it
# runs on macOS too; CI runs it in the Linux job.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
"${CXX:-c++}" -std=c++17 -Wall -Wextra -Werror -I "$ROOT/linux/runner" \
  "$ROOT/linux/runner/undo_shortcut_test.cc" -o "$OUT/undo_shortcut_test"
"$OUT/undo_shortcut_test"
