#!/usr/bin/env bash
# Turn rendered PNG frames into the onboarding assets (animated loop + still).
#   usage: scripts/export-webp.sh <composition-id> <beat-number> <still-frame-number> [quality] <theme>
#   e.g.   scripts/export-webp.sh m1-welcome 1 118 70 marine
# Input : renders/<composition-id>-<theme>-frames/frame_000001.png ... (30 fps, 150 frames)
# Output: ../../assets/onboarding/beat_<n>_loop_${theme}.webp   (animated, 5 s, loops)
#         ../../assets/onboarding/beat_<n>_still_${theme}.webp  (one representative frame)
# Per-frame durations alternate 33/34 ms so the loop lasts exactly 5000 ms.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo="$(cd "$here/../../.." && pwd)"
id="${1:?composition id}"
beat="${2:?beat number 1-3}"
still="${3:?still frame number, 1-based}"
q="${4:-70}"
theme="${5:?theme: hell, dunkel or marine}"
frames="$here/renders/$id-$theme-frames"
out="$repo/assets/onboarding"
mkdir -p "$out"
[ -d "$frames" ] || { echo "render first: $frames missing" >&2; exit 1; }

# Build the img2webp argument list: one "-d <ms> <frame>" pair per frame.
args=(-loop 0 -lossy -q "$q" -m 6)
n=0
for f in "$frames"/frame_*.png; do
  t0=$(( n * 1000 / 30 ))
  t1=$(( (n + 1) * 1000 / 30 ))
  args+=(-d $(( t1 - t0 )) "$f")
  n=$(( n + 1 ))
done
[ "$n" -eq 150 ] || { echo "expected 150 frames, got $n" >&2; exit 1; }

img2webp "${args[@]}" -o "$out/beat_${beat}_loop_${theme}.webp"

stillsrc=$(printf "%s/frame_%06d.png" "$frames" "$still")
cwebp -quiet -q 85 "$stillsrc" -o "$out/beat_${beat}_still_${theme}.webp"

ls -l "$out/beat_${beat}_loop_${theme}.webp" "$out/beat_${beat}_still_${theme}.webp" | awk '{print $5, $9}'
