#!/usr/bin/env bash
# Compiles and runs the Linux push-to-talk autorepeat filter unit test
# (linux/runner/autorepeat_filter_test.cc). Platform-neutral C++17, so it
# runs on macOS too; CI runs it in the Linux job.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
"${CXX:-c++}" -std=c++17 -Wall -Wextra -Werror -I "$ROOT/linux/runner" \
  "$ROOT/linux/runner/autorepeat_filter_test.cc" -o "$OUT/autorepeat_filter_test"
"$OUT/autorepeat_filter_test"
