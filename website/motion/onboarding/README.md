# Onboarding welcome loops (M1-M3)

HyperFrames source for the three platform-neutral loops of the onboarding
welcome page (ticket 13, `internal-notes`).
The shipped files live in `assets/onboarding/` (see its README); this folder is
the versioned source they are rendered from.

| Loop | Composition | Beat slot | Shows |
|---|---|---|---|
| M1 Welcome | `compositions/m1-welcome.html` | beat 1 | waveform pill, the words land in an abstract text field |
| M2 Speech recognition | `compositions/m2-recognition.html` | beat 2 | a chip on the device becomes the pill (local, no cloud arrow) |
| M3 Access | `compositions/m3-access.html` | beat 3 | microphone and paste as a two-step list with an amber progress marker |

Rules that apply to every loop:

- No text in the image. Captions stay in the ARB files.
- No operating-system window chrome, no brand, no product UI.
- Colours are tokens from `design-tokens/primitives.tokens.json` only
  (navy stage, glacier light bands, cyan for action and recording, amber for
  the warm marker). `scripts/check-tokens.mjs` fails on any other hex value,
  rgb() or hsl().
- 920 x 576 px (16:10, the 2x size of the 460 x 288 onboarding panel),
  5.0 s, 30 fps, seamless: the first and the last frame show the same state.
- Layout is positioned with transforms and fixed anchors. Lint rejects
  `left`/`top` tweens (`gsap_non_transform_motion`).

## Layout

```
website/motion/onboarding/
  compositions/      source of truth, one standalone HTML file per loop
  scripts/
    stage.sh         copies one composition to .stage/<id>/index.html (lint/check/render need a project)
    check-tokens.mjs colour guard against design-tokens
    export-webp.sh  PNG frames -> animated WebP loop + still WebP in assets/onboarding/
    render-all.sh   the whole pipeline for all three loops
  package.json       pins hyperframes 0.8.177 and gsap 3.14.2 (GSAP is vendored from node_modules, no CDN at render time)
```

`.stage/`, `renders/` and `node_modules/` are gitignored.

## Render

Requirements: Node 20+, `libwebp` tools (`img2webp`, `cwebp`, from Homebrew
`webp`). No Docker.

```bash
cd motion/onboarding
npm install
npm run render                 # colour guard, lint, PNG frames, WebP export for all three
```

Single loop, step by step:

```bash
cd motion/onboarding
node scripts/check-tokens.mjs
S=$(scripts/stage.sh m1-welcome)
npx hyperframes lint "$S"
npx hyperframes render "$S" --format png-sequence --fps 30 --quality delivery -o renders/m1-welcome-frames
scripts/export-webp.sh m1-welcome 1 118 80
```

`export-webp.sh <id> <beat> <still-frame> [quality]`:

- Loop: `img2webp -lossy -q <quality> -m 6`, one frame per PNG at 30 fps with
  33/34 ms durations, so the loop lasts exactly 5000 ms.
- Still: `cwebp -q 85` of one representative frame (1-based frame number).
  The still is a frame where the loop reads clearly (M1 118, M2 91, M3 118),
  not the first frame. The first frame of M1 and M3 is an empty state.

Frame checks: `npx hyperframes check "$S"` runs the runtime, layout and
contrast passes in headless Chrome. Look at contact sheets built from the
rendered frames (`ffmpeg ... tile=3x3`) before shipping a change.

## Where M2 and M3 plug in

On `dev` the welcome page has three beat slots (`welcome_step.dart`,
`onboardingBeatAssetPath`). Beat 1 to 3 carry M1 to M3, and the beat text of
each slot matches its loop. When the v3 flow (tickets 01/02/05, the
`feat/onboarding-v3-flow` branch) puts the speech and access steps in place,
the loops move with their steps:

- M2 belongs on the speech step (S2, model choice and local recognition).
  Show it via `onboardingBeatAssetPath` on that step's media panel with the
  same `_still_` fallback.
- M3 belongs on the access step (S3, microphone and paste). Its steps mirror
  the microphone and the auto-paste permission rows there.

Asset names are `beat_<n>_{loop,still}_<theme>.webp` with the themes `hell`,
`dunkel` and `marine`. The mapping is the single function `onboardingBeatAssetPath`,
which takes the theme from `onboardingBeatTheme()`.

## Measurements

See the ticket's Comments entry and `assets/onboarding/README.md` for the
numbers of the shipped files (size, frame count, duration) and the idle-CPU
method.

## Themes

`themes/hell.css`, `themes/dunkel.css` and `themes/marine.css` are generated from
`design-tokens/` by `scripts/build-themes.mjs`. Each composition reads only role
variables (`--stage`, `--panel`, `--action`, `--highlight`, ...), so a new
accent or theme needs a re-render, not a composition change. Cyan carries action
and recording; amber (`--highlight`) is the warm waveform and progress accent.
Render one theme at a time: `scripts/stage.sh <id> <theme>`, then the render
commands above. `scripts/contact-sheet.py <theme> <out.png>` builds a review sheet.
