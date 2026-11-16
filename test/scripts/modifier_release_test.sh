#!/usr/bin/env bash
# Compiles and runs the Linux modifier-release unit test
# (linux/runner/modifier_release_test.cc). Platform-neutral C++17, so it
# runs on macOS too; CI runs it in the Linux job.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
"${CXX:-c++}" -std=c++17 -Wall -Wextra -Werror -I "$ROOT/linux/runner" \
  "$ROOT/linux/runner/modifier_release_test.cc" -o "$OUT/modifier_release_test"
"$OUT/modifier_release_test"
