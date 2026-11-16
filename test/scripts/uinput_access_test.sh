#!/usr/bin/env bash
# Compiles and runs the uinput access unit test
# (linux/runner/uinput_access_test.cc). Platform-neutral C++17, so it
# runs on macOS too; CI runs it in the Linux job.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
"${CXX:-c++}" -std=c++17 -Wall -Wextra -Werror -I "$ROOT/linux/runner" \
  "$ROOT/linux/runner/uinput_access_test.cc" -o "$OUT/uinput_access_test"
"$OUT/uinput_access_test"
