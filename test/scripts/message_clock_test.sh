#!/usr/bin/env bash
# Compiles and runs the Windows message-time stamps test
# (windows/runner/message_clock_test.cc). Platform-neutral C++17, so it
# runs on macOS too; CI runs it in the Linux job.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
"${CXX:-c++}" -std=c++17 -Wall -Wextra -Werror -I "$ROOT/windows/runner" \
  "$ROOT/windows/runner/message_clock_test.cc" -o "$OUT/message_clock_test"
"$OUT/message_clock_test"
