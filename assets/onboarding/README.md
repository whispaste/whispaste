# Onboarding beat clips (page 1)

Short, looping screen recordings of the real app — one per demo beat on the
first onboarding page. **Not produced yet**: until a file lands here, the media
panel renders its icon placeholder, per beat and per variant. Dropping a file
in is the entire activation step; no code change is needed.

## File names

```
beat_{1,2,3}_loop_{dark,light}.webp    animated, ~2–3 s, seamless loop
beat_{1,2,3}_still_{dark,light}.webp   single frame (the loop's first frame)
```

The index matches the beat order on the page: 1 = `onboardingBeat1Title`,
2 = `onboardingBeat2Title`, 3 = `onboardingBeat3Title`. Record each clip to
match the beat's own claim, not the app in general.

Every file is optional and independent. A dark-only delivery renders correctly
(light theme keeps the placeholder), and so does a loop-only one — except for
reduced motion, see below.

## Why a separate `_still_` file

An animated WebP cannot be paused. When the system's "Reduce Motion" /
"Disable animations" setting is on, the page loads the `_still_` file instead
of the loop. Without it, a reduced-motion user gets the placeholder — the loop
is never shown stopped.

## Target size

**460 × 288 logical px** — that is **16 : 10** — at the fixed 1100 × 720
onboarding window. Export at 2×, i.e. **920 × 576 px**, for a crisp result on
Retina displays.

The surface renders with `BoxFit.cover`, so the aspect ratio matters more than
the exact pixel count: a clip that is off-ratio gets cropped at the edges
rather than letterboxed. Keep the meaningful action away from the outer ~5 %.

The authoritative numbers are `kOnboardingBeatMediaWidth` /
`kOnboardingBeatMediaHeight` in
`lib/features/onboarding/steps/welcome_step.dart` — if the page geometry ever
changes, they change with it and this file must follow.

## Recording notes

Real app, real mouse movement, on a desktop background (the reference this
page is modelled on shows the product in situ, not a bare window). Speech has
to be genuinely spoken for the transcript to look real.
