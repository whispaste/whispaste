#!/usr/bin/env bash
# Builds and runs the offline libei sender test (see eis_keyboard_test.cc).
# Needs libei-dev (headers only; libei.so.1 is loaded at run time) and
# libeis1 (linked by full name, no libeis-dev header is needed).
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
runner="$here/../../linux/runner"
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT

libeis="$(ls /usr/lib/x86_64-linux-gnu/libeis.so.1 /usr/lib/libeis.so.1 2>/dev/null | head -n1 || true)"
if [[ -z "$libeis" ]]; then
  echo "libeis.so.1 not found (package libeis1)" >&2
  exit 2
fi

g++ -std=c++17 -O2 -Wall -Wextra -pthread -DWHISPASTE_HAVE_LIBEI \
  -I"$runner" -I/usr/include/libei-1.0 \
  "$here/eis_keyboard_test.cc" "$runner/eis_keyboard_sender.cc" \
  "$libeis" -ldl -o "$out/eis_keyboard_test"

"$out/eis_keyboard_test"
