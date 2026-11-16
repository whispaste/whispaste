#!/usr/bin/env bash
# Compiles and runs the Linux `--diagnose` launch decision unit test
# (linux/runner/diagnose_launch_test.cc). Platform-neutral C++17, so it runs
# on macOS too; CI runs it in the Linux job.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
"${CXX:-c++}" -std=c++17 -Wall -Wextra -Werror -I "$ROOT/linux/runner" \
  "$ROOT/linux/runner/diagnose_launch_test.cc" -o "$OUT/diagnose_launch_test"
"$OUT/diagnose_launch_test"
