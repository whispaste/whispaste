#!/usr/bin/env bash
# One review MP4 per beat with the three themes side by side (hell | dunkel | marine).
#   usage: scripts/preview-mp4.sh <composition-id> <out.mp4>
# Reads renders/<id>-<theme>-frames/frame_NNNNNN.png (30 fps). Review only; the app
# ships the WebP files from export-webp.sh.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
id="${1:?composition id}"
out="${2:?output mp4}"
cd "$here"
ffmpeg -y -loglevel error \
  -framerate 30 -i "renders/$id-hell-frames/frame_%06d.png" \
  -framerate 30 -i "renders/$id-dunkel-frames/frame_%06d.png" \
  -framerate 30 -i "renders/$id-marine-frames/frame_%06d.png" \
  -filter_complex "[0:v][1:v][2:v]hstack=inputs=3,format=yuv420p[v]" \
  -map "[v]" -c:v libx264 -crf 20 -preset slow -movflags +faststart "$out"
echo "$out"
