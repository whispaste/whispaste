# WhisPaste design tokens

One platform-neutral source for colour, type, spacing, radius, depth and motion.
The website consumes it today; the desktop app is meant to consume the same
files when its theme is refactored (`lib/core/theme/` already uses the same
scales: `WpSpacing`, `WpRadius`, `WpMotion`, `WpColorsDark`).

## Files

| File | Layer | Rule |
|---|---|---|
| `primitives.tokens.json` | Raw values: palette, font families/sizes, space, radius, shadow, duration, easing, z-index, breakpoints | Never referenced by components. |
| `semantic.dark.tokens.json` | Roles for the dark stage (default, and the app's only mode) | Same keys as the light file. |
| `semantic.light.tokens.json` | Roles for light "glacier" bands | Same keys as the dark file. |
| `components.tokens.json` | One group per component (`button`, `card`, `input`, `prose`, …) | Points at semantic tokens only. |

The format follows the W3C Design Tokens (DTCG) shape: `$type`, `$value`,
`$description`, aliases written as `{group.token}`. Fluid sizes carry
`$extensions.fluid` with `min`/`max` (and optional `minVw`/`maxVw`); platforms
without viewport scaling use `$value`.

## Colour roles ("Glacier + Amber")

- **Navy stage** (`navy.*`): the ambient dark wash, hero and most bands.
- **Deep ink** (`navy.950`): darker bands for tonal contrast.
- **Glacier** (`glacier.*`): light bands where results and everyday use cases sit.
  Cool blue-grey, never cream or paper.
- **Cyan** (`cyan.*`): action and recording. Buttons, focus, waveform, active states.
- **Amber** (`amber.*`): the warm accent. Markers behind single words, hints,
  callouts, FAQ icons. Never a button fill, never a large surface.
- **Violet** (`navy.500`): only as the last stop of the stage wash.
- **Status**: success/warning/error match the app; each has an on-light variant.

## Modes on the website

`src/styles/tokens.css` declares dark values on `:root` and light values on
`[data-surface="light"]`. Any element can switch:

```html
<section class="wp-band" data-surface="light"> … </section>
```

Everything inside (components, Tailwind `text-ink*` utilities, legacy
variables) follows that mode. Chrome that must stay dark inside a light band
sets `data-surface="dark"` on itself.

## Build

```bash
cd website
npm run tokens        # regenerate src/styles/tokens.css
npm run tokens:check  # fail if the CSS is stale
npx vitest run scripts/__tests__/design-tokens.test.ts
```

The test also checks WCAG AA contrast for every text role on every band and
card surface in both modes.

## Catalogue

`npm run dev` → `/design-system/` shows every token and every shared
component (`src/styles/components.css`: `.wp-btn`, `.wp-chip`, `.wp-tag`,
`.wp-card`, `.wp-callout`, `.wp-kbd`, `.wp-field`/`.wp-input`, `.wp-table`,
`.wp-prose`, `.wp-marker`, `.wp-band`) on a dark and a light surface. The
route exists only in the dev server.

## Rules for new code

1. Read `--wp-<component>-*` tokens; add a component group before inventing a value.
2. No hex, rgba or raw durations in component styles. Device mock-ups that
   mirror real app or OS pixels (`AppScreenshots`, `AppPasteDemo`, the
   overlay mock-up) are the documented exception.
3. Every text/surface pair must keep AA in both modes; the token test enforces
   it for the semantic roles.
4. Blog and other Markdown content renders inside `.wp-prose`, which styles
   every element the renderer can emit.
