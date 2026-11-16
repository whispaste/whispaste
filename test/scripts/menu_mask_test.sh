#!/usr/bin/env bash
# Compiles and runs the menu-mask unit test (linux/runner/menu_mask_test.cc).
# Platform-neutral C++17, so it runs on macOS too; CI runs it in the Linux job.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
"${CXX:-c++}" -std=c++17 -Wall -Wextra -Werror -I "$ROOT/linux/runner" \
  "$ROOT/linux/runner/menu_mask_test.cc" -o "$OUT/menu_mask_test"
"$OUT/menu_mask_test"
