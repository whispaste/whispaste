# Feature-Spotlight mini-screenshots

Static screenshots for `FeatureSpotlightEntry.image` (`lib/core/
feature_spotlight/feature_spotlight.dart`), shown above an entry's title/
description in the spotlight dialog (`feature_spotlight_notice.dart`).
Mirrors `assets/onboarding/README.md`'s capture convention, scaled to this
dialog's narrower card instead of the full onboarding page. If a file is
missing, the entry still renders — just without the image (see
`FeatureSpotlightEntry.image`'s doc comment).

## File names

One static file per registry entry, named after the entry's `id`:

```
snippet_picker.webp
side_panel.webp
```

## Target size

**340 × 212 logical px** (~16:10, same ratio as the onboarding clips) — the
dialog's content width after `WpSpacing.lg` padding on both sides of the
380 px container (`_FeatureSpotlightDialog` in `feature_spotlight_notice
.dart`). Export at 2×, i.e. **680 × 424 px**, for a crisp result on Retina
displays.

Renders with `BoxFit.cover`, so the ratio matters more than the exact pixel
count — an off-ratio image gets cropped at the edges. Keep the meaningful
content away from the outer ~5%.

## No `_loop`/`_still` variants

Unlike the onboarding beat clips, these are static images only — a
one-sentence spotlight hint doesn't carry the same case for motion, and a
static screenshot has no Reduce-Motion concern to begin with.

## Recording notes

Same spirit as the onboarding clips: real app, on a real (tidied) desktop
background — the product in situ, not a bare, freestanding window. A single
screenshot is used for every viewer regardless of their own OS; for a
feature that ships identically on multiple platforms, capture on whichever
platform gives the cleanest, most chrome-free crop rather than producing a
variant per platform.
