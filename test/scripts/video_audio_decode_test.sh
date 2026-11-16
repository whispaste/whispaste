#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
python3 "$ROOT/test/scripts/video_decoder_download_test.py"
python3 "$ROOT/scripts/build-video-decoder.py" --platform linux
python3 "$ROOT/test/scripts/video_audio_decode_test.py" \
  "$ROOT/.build/video-decoder/linux/ffmpeg"
