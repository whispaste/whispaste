#!/usr/bin/env bash
# Build the theme CSS, colour-guard the sources, then stage, lint, render and
# export every loop in every theme. One composition at a time, at the lowest CPU
# priority, so a busy Mac is not slowed down further.
#   usage: npm run render   (or bash scripts/render-all.sh)
# Writes renders/<id>-<theme>-frames/ (PNG frames, gitignored) and the shipped
# assets under assets/onboarding/ (repo root). Renders drive headless Chrome.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$here"

node scripts/build-themes.mjs >/dev/null
node scripts/check-tokens.mjs

# id  beat  still-frame (1-based, 30 fps)  webp quality
# beat 4 = auto-paste (still after the paste), beat 5 = hold-to-talk (pill open)
jobs=(
  "m1-welcome 1 118 70"
  "m2-recognition 2 91 70"
  "m3-access 3 118 70"
  "m4-autopaste 4 110 70"
  "m5-hotkey 5 60 70"
)
themes=(marine hell dunkel)
for theme in "${themes[@]}"; do
  for job in "${jobs[@]}"; do
    read -r id beat still quality <<<"$job"
    stage="$(scripts/stage.sh "$id" "$theme")"
    nice -n 19 npx hyperframes lint "$stage"
    nice -n 19 npx hyperframes render "$stage" --format png-sequence --fps 30 --quality delivery \
      -o "renders/$id-$theme-frames" --quiet
    scripts/export-webp.sh "$id" "$beat" "$still" "$quality" "$theme"
  done
done
