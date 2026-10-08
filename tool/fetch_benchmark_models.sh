#!/usr/bin/env bash
# fetch_benchmark_models.sh — downloads the STT models the headless latency
# benchmark (.github/workflows/headless-benchmark.yml) runs against, in the
# app's own on-disk layout (<sttDir>/ggml-*.bin, <sttDir>/parakeet-tdt-0.6b-v3/),
# so the directory can be mounted as the app's models/stt directory as is.
#
# Same sources the app downloads from (lib/services/model_download_service.dart,
# lib/services/stt_parakeet/parakeet_model_registry.dart). whisper-small is the
# smallest catalog model (Compact tier) — enough to catch a pipeline/engine
# regression while keeping the download and runner time low.
#
# Usage: tool/fetch_benchmark_models.sh <dest-dir>
set -euo pipefail

DEST="${1:?usage: fetch_benchmark_models.sh <dest-dir>}"
mkdir -p "$DEST/parakeet-tdt-0.6b-v3"

fetch() {
  curl -fsSL --retry 3 --retry-delay 5 -o "$2.part" "$1"
  mv "$2.part" "$2"
}

WHISPER_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small-q5_1.bin"
WHISPER_SHA256="ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb"
fetch "$WHISPER_URL" "$DEST/ggml-small-q5_1.bin"
echo "$WHISPER_SHA256  $DEST/ggml-small-q5_1.bin" | sha256sum -c -

PARAKEET_BASE="https://huggingface.co/csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8/resolve/main"
for file in encoder.int8.onnx decoder.int8.onnx joiner.int8.onnx tokens.txt; do
  fetch "$PARAKEET_BASE/$file" "$DEST/parakeet-tdt-0.6b-v3/$file"
done

ls -lR "$DEST"
