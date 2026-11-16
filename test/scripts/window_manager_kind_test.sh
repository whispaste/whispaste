#!/usr/bin/env bash
# Compiles and runs the Linux tiling-WM detection unit test
# (linux/runner/window_manager_kind_test.cc, XP-6-10). Platform-neutral
# C++17, so it runs on macOS too; CI runs it in the Linux job.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
"${CXX:-c++}" -std=c++17 -Wall -Wextra -Werror -I "$ROOT/linux/runner" \
  "$ROOT/linux/runner/window_manager_kind_test.cc" -o "$OUT/window_manager_kind_test"
"$OUT/window_manager_kind_test"
