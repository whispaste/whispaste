#!/usr/bin/env bash
# Compiles and runs the Windows undo decisions test
# (windows/runner/undo_policy_test.cc). Platform-neutral C++17, so it
# runs on macOS too; CI runs it in the Linux job.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
"${CXX:-c++}" -std=c++17 -Wall -Wextra -Werror -I "$ROOT/windows/runner" \
  "$ROOT/windows/runner/undo_policy_test.cc" -o "$OUT/undo_policy_test"
"$OUT/undo_policy_test"
