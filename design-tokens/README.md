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
  callouts, FAQ icons, and targeted accent surfaces: the dock's primary
  "Diktieren" call to action, the overlay and button background option, and
  larger landing-page areas. WCAG AA stays mandatory on amber: text and icons
  on it use the dark ink (`navy.900`, about 10.5:1). A foreground that cannot
  reach 3:1 on an amber surface takes the dark ink instead. For the wave the
  overlay first tries the darker step of the same hue (cyan 600, then cyan 700
  at about 4.1:1), so the wave stays cyan; the done check goes straight to ink.
- **Violet** (`navy.500`): only as the last stop of the stage wash.
- **Coffee yellow** (`coffee.*`, Kaffee-Gelb `#FFDD00`): only the "buy me a
  coffee" support buttons (Ko-fi and Buy Me a Coffee at equal rank), in the app
  (`WpCoffeeTokens`) and on the website (`coffee-button`). Ink is `navy.900`
  (about 15:1). Never used for other accents, so these buttons stay the only
  yellow things on a screen.
- **Status**: success/warning/error match the app; each has an on-light variant.

## App overlay presets

`app.tokens.json` carries the `overlay.*` group (ADR 0024): background presets
(`marine`, `graphit`, `gletscher`, `amber`), each a single flat fill (no
gradient, no sheen, no specular streak), wave presets (`cyan`, `violett`,
`ink`, `amber`) with a dark and a light value each, plus a darker light
step (`light-strong`) that the overlay uses when the light value falls below
3:1 on the fill, and the signal colours per tone. The generator emits them as `WpOverlayTokens`. Users pick a background
and a wave independently; there is no free colour picker.

The default overlay of the Marine design is the amber background with the ink
wave, in the compact size, with the static outline (no fluid outline motion);
`components.tokens.json` → `overlay` carries exactly this look for the website,
so the site shows the overlay a new installation shows.

## App switch track

`app.tokens.json` (desktop app, ADR 0017) carries `switch-track-off`: the
track of an off switch. The white thumb must reach 3:1 on it and the track
3:1 on the window ground (WCAG 1.4.11). Journal (light, and the navy set)
uses `glacier.600` (6.34:1 thumb, 5.41:1 ground); stage (dark) uses
`glacier.500` (4.33:1 thumb, 4.28:1 ground). Lighter tracks such as
`frost.400` fail the thumb check on dark.

`selection-border` (journal and stage, same value `#6B7A96`): the boundary of an
unselected colour swatch, 3:1 or better on every surface of both sets. A
single value is used because it passes on both, so it needs no per-theme pair.

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

Teststrategie 2026-10-30: tests cover only business logic, hand-over points and
guard checks. Design is not tested. Contrast, spacing, sizes and overflow are
design requirements that are judged by visual review and by the generators in
`generators/`, not by test runs.

What stays as guard (Schutzprüfung, token drift) is a static lint that stops
values from bypassing the token system:

- `node scripts/color-literals.mjs [--verbose]`: hex, rgb()/hsl(), Tailwind
  palette utilities, named white/black and SVG colour attributes outside
  `tokens.css`. Mock-ups of the app or an OS window are fenced with
  `mockup-colours:start` / `mockup-colours:end`; the `theme-color` meta is
  exempt because browsers read it before CSS.
- `node scripts/design-lint.mjs [--verbose] [rule]`: `font-size` and
  `border-radius` written as lengths, padding/margin/gap off the 4px grid
  (scale values become `--wp-space-*`), transition durations written as
  ms/s, and Tailwind arbitrary lengths such as `text-[15px]`. Run by hand as a
  review aid; it is not a test.

Not checks any more: the token contrast test (`design-tokens.test.ts`) and the
planned rendered-contrast check (Playwright). They are design tests and are to
be removed from the test runs (Teststrategie 2026-10-30). Contrast stays a
requirement (WCAG AA, rule 4 below).

The same token JSON feeds the Dart theme. Token drift between the JSON and the
generated Dart file remains a guard (`tool/design_tokens/generate_dart.dart`).

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
4. Every text/surface pair must keep AA in both modes. This is a design
   requirement, checked by visual review (not by a test since 2026-10-30).
5. Blog and other Markdown content renders inside `.wp-prose`, which styles
   every element the renderer can emit.
