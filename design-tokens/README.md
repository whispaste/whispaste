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
- **Deep ink** (`navy.950`): reserved for tonal depth inside graphics; never a
  full-width band (a darker band behind cards reads as a hole).
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

Two light bands placed directly after each other join into one sheet: the
inner corners go square and a 1px `--wp-border-subtle` rule sits on the seam
(`components.css`). Never leave two rounded light sheets touching; they meet
in a notch.

## Build

```bash
cd website
npm run tokens        # regenerate src/styles/tokens.css + src/scripts/overlay-tokens.generated.ts
npm run tokens:check  # fail if either output is stale
npx vitest run scripts/__tests__/design-tokens.test.ts
```

### Recording overlay (`overlay.*`)

The fluid recording pill is the one component shared 1:1 between website and
app. Its shape, wobble, timings and states stay in the app's
`OverlayDesignSpec`; only its colours live here: a flat navy fill
(`overlay.fill`), cyan for the live dot, progress line and hairline
(`overlay.accent`), and a flat, fully opaque amber waveform (`overlay.wave`).
The canvas renderer can't read CSS variables, so the build also writes the
group as hex constants to `website/src/scripts/overlay-tokens.generated.ts`.
The app still paints its old navy→violet/teal colours until it adopts these.

## Checks

Three layers catch values that bypass the system before anyone sees them:

1. **Token contrast** (`design-tokens.test.ts`): every text role on every band
   and card surface in both modes meets WCAG AA; text on the solid accent fill
   too. Translucent surfaces are composited onto the band before measuring.
2. **Static lint** (also in `design-tokens.test.ts`, runnable by hand):
   - `node scripts/color-literals.mjs [--verbose]`: hex, rgb()/hsl(), Tailwind
     palette utilities, named white/black and SVG colour attributes outside
     `tokens.css`. Mock-ups of the app or an OS window are fenced with
     `mockup-colours:start` / `mockup-colours:end`; the `theme-color` meta is
     exempt because browsers read it before CSS.
   - `node scripts/design-lint.mjs [--verbose] [rule]`: `font-size` and
     `border-radius` written as lengths, padding/margin/gap off the 4px grid
     (scale values become `--wp-space-*`), transition durations written as
     ms/s, and Tailwind arbitrary lengths such as `text-[15px]`.
3. **Rendered contrast**: Playwright checks text against its effective
   background on every route (planned, see the website test suite).

The same checks transfer to the app: the JSON feeds the Dart theme, and a
Dart lint can flag `Color(0x…)`, `EdgeInsets` and `BorderRadius` literals the
way `design-lint.mjs` flags CSS.

## Catalogue

`npm run dev` → `/design-system/` shows every token and every shared
component (`src/styles/components.css`: `.wp-btn`, `.wp-chip`, `.wp-tag`,
`.wp-card`, `.wp-callout`, `.wp-kbd`, `.wp-field`/`.wp-input`, `.wp-table`,
`.wp-prose`, `.wp-marker`, `.wp-band`) on a dark and a light surface. The
route exists only in the dev server.

## Reference capture

`reference/landingpage-de-2026-10-17.webp` is a full-page capture of the
German landing page (1425 px wide, header to footer) after every section was
moved onto this system. Compare later redesigns against it.

## Rules for new code

1. Read `--wp-<component>-*` tokens; add a component group before inventing a value.
2. No hex, rgba, raw font sizes, radii, durations or off-grid spacing in
   component styles. Device mock-ups that mirror real app or OS pixels
   (`AppScreenshots`, `AppPasteDemo`, `HeroExample`, the overlay mock-up) are
   the documented exception for colour.
3. Type sizes come from the scale only: `2xs`–`xl` for UI text, then the fluid
   `lead`, `card-title`, `h3`, `title`, `h2`, `h1`, `display`. A heading that
   fits none of them is a reason to discuss the scale, not to add a `clamp()`.
4. Every text/surface pair must keep AA in both modes; the token test enforces
   it for the semantic roles.
5. Blog and other Markdown content renders inside `.wp-prose`, which styles
   every element the renderer can emit.
