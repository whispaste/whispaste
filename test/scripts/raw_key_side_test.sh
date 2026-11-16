#!/usr/bin/env bash
# Compiles and runs the Raw Input side test (windows/runner/raw_key_side_test.cc).
# Platform-neutral C++17, so it runs on macOS and Linux too; CI runs it in the
# Linux job next to menu_mask.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
"${CXX:-c++}" -std=c++17 -Wall -Wextra -Werror -I "$ROOT/windows/runner" \
  "$ROOT/windows/runner/raw_key_side_test.cc" -o "$OUT/raw_key_side_test"
"$OUT/raw_key_side_test"
