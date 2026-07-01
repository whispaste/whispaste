#!/usr/bin/env bash
# build-store-trailer.sh — encode raw demo clip(s) into an MS-Store-conformant
# trailer + 1920x1080 thumbnail. Local, ffmpeg-only (no cloud, no cost).
#
# Usage:
#   scripts/build-store-trailer.sh <clip1.mp4> [clip2.mp4 ...] [--out dir]
#
# Inputs are concatenated (in order), then encoded to MS Store trailer spec:
#   MP4 / faststart (moov atom at front) · H.264 High Profile · 1920x1080
#   · ~50 Mbps · yuv420p · 2 B-frames · CABAC · AAC-LC stereo 48 kHz 384 kbps
#   · hard-capped at 60 s (store recommendation).
# Source: learn.microsoft.com/.../screenshots-and-images (trailer requirements)
#
# Outputs (in --out, default store/_build/): trailer.mp4, trailer-thumb.png
#
# NOT in scope (follow-up steps):
#   - multi-clip transitions / branding overlays  (needs motion design)
#   - WebVTT captions                            (needs a local Whisper setup)
#
# Requires: ffmpeg >= 4.x (present on this machine: 8.1.1).

set -euo pipefail

OUT="store/_build"
CLIPS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) OUT="$2"; shift 2 ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) CLIPS+=("$1"); shift ;;
  esac
done

[[ ${#CLIPS[@]} -gt 0 ]] || { echo "Usage: $0 <clip1.mp4> [clip2.mp4 ...] [--out dir]" >&2; exit 1; }
command -v ffmpeg >/dev/null 2>&1 || { echo "ffmpeg not found" >&2; exit 1; }

mkdir -p "$OUT"
CONCAT_LIST="$(mktemp)"
trap 'rm -f "$CONCAT_LIST"' EXIT
for c in "${CLIPS[@]}"; do
  [[ -f "$c" ]] || { echo "missing input: $c" >&2; exit 1; }
  printf "file '%s'\n" "$(cd "$(dirname "$c")" && pwd)/$(basename "$c")" >> "$CONCAT_LIST"
done

TRAILER="$OUT/trailer.mp4"
THUMB="$OUT/trailer-thumb.png"
INPUT_ARGS=()
if [[ ${#CLIPS[@]} -eq 1 ]]; then
  INPUT_ARGS=(-i "${CLIPS[0]}")
else
  INPUT_ARGS=(-f concat -safe 0 -i "$CONCAT_LIST")
fi

# Detect audio in the first input. Playwright web captures have no audio
# stream; synthesize a silent AAC track in that case so the output stays
# MS-Store-conformant (AAC-LC stream required even when mute).
HAS_AUDIO=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_type -of csv=p=0 "${CLIPS[0]}" 2>/dev/null | head -1)

# Concat + encode to MS Store spec. -vf scales/pads any aspect to 1920x1080.
FF=(ffmpeg -hide_banner -loglevel warning "${INPUT_ARGS[@]}")
if [[ "$HAS_AUDIO" != "audio" ]]; then
  FF+=(-f lavfi -i anullsrc=channel_layout=stereo:sample_rate=48000)
fi
FF+=(
  -t 60
  -vf "scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2,setsar=1,fps=30"
  -map 0:v:0
  -c:v libx264 -profile:v high -b:v 50M -maxrate 50M -bufsize 100M
  -x264-params "bframes=2:cabac=1" -pix_fmt yuv420p
)
if [[ "$HAS_AUDIO" == "audio" ]]; then
  FF+=(-map 0:a:0 -c:a aac -b:a 384k -ar 48000 -ac 2)
else
  FF+=(-map 1:a:0 -shortest -c:a aac -b:a 384k)
fi
FF+=(-movflags +faststart -y "$TRAILER")
"${FF[@]}"

# Thumbnail at ~1 s in (fallback: first frame for very short clips).
ffmpeg -hide_banner -loglevel error -ss 1 -i "$TRAILER" -frames:v 1 -y "$THUMB" 2>/dev/null \
  || ffmpeg -hide_banner -loglevel error -i "$TRAILER" -frames:v 1 -y "$THUMB"

echo "✓ $TRAILER"
echo "✓ $THUMB"
echo "  size: $(du -h "$TRAILER" | cut -f1) · length: $(ffprobe -v error -show_entries format=duration -of csv=p=0 "$TRAILER" | cut -d. -f1)s"
