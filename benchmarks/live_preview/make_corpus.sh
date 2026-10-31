#!/usr/bin/env bash
# Regenerates the replay corpus (gitignored output) from corpus_src/*.txt with macOS `say`.
# Usage: bash benchmarks/live_preview/make_corpus.sh
# Output: benchmarks/live_preview/corpus/<name>.wav (16 kHz mono 16-bit PCM).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
out="$here/corpus"
mkdir -p "$out"
voice_for() {
  case "$1" in
    de_short) echo "Anna" ;;
    de_medium) echo "Eddy (Deutsch (Deutschland))" ;;
    de_long1|de_long2) echo "Reed (Deutsch (Deutschland))" ;;
    en_short) echo "Samantha" ;;
    en_medium) echo "Daniel" ;;
    en_long1|en_long2) echo "Karen" ;;
    *) echo "unknown corpus item: $1" >&2; exit 1 ;;
  esac
}
for src in "$here"/corpus_src/*.txt; do
  name="$(basename "$src" .txt)"
  voice="$(voice_for "$name")"
  say -v "$voice" -f "$src" -o "$out/$name.wav" --file-format=WAVE --data-format=LEI16@16000
  echo "$name: $voice"
done
