#!/usr/bin/env bash
# Builds and runs the headless Linux audio import decoder test (WP-35b):
# linux/runner/audio_file_decode_core.cc against libopusfile and libFLAC,
# fixtures from test/fixtures/audio_import/. Needs the dev packages
# libopusfile-dev and libflac-dev (see BUILD.md, Linux section).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
# shellcheck disable=SC2046
"${CXX:-c++}" -std=c++17 -Wall -Wextra -Werror -O2 \
  -I "$ROOT/linux/runner" \
  $(pkg-config --cflags opusfile flac) \
  "$ROOT/linux/runner/audio_file_decode_core.cc" \
  "$ROOT/linux/runner/audio_file_decode_gst.cc" \
  "$ROOT/linux/runner/audio_file_decode_test.cc" \
  $(pkg-config --libs opusfile flac) -ldl \
  -o "$OUT/audio_file_decode_test"
"${CXX:-c++}" -std=c++17 -Wall -Wextra -Werror -O2 \
  -I "$ROOT/linux/runner" \
  "$ROOT/linux/runner/mp4_gapless.cc" \
  "$ROOT/linux/runner/mp4_gapless_test.cc" \
  -o "$OUT/mp4_gapless_test"
"$OUT/mp4_gapless_test" "$ROOT/test/fixtures/audio_import"
"$OUT/audio_file_decode_test" "$ROOT/test/fixtures/audio_import" "$OUT"
