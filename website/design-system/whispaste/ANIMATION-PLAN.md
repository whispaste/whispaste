# WhisPaste App Preview Animation Plan

## Concept

An animated cursor demonstration on the AppPreviewMockup component that walks through a typical workflow: **recording a transcription → viewing in history → applying Smart Mode → copying the result**. The cursor acts as a silent narrator, guiding the viewer's eye through the product's core value loop in a single ~12 s cycle.

## Animation Sequence (4 scenes, ~12 s total loop)

### Scene 1: "Start Recording" (3 s)

1. Cursor fades in and moves to the floating FAB (mic button).
2. FAB receives a pulse/click animation (scale bounce + ring ripple).
3. A brief overlay mockup appears showing the recording state (waveform hint, elapsed timer).
4. **Transition:** overlay fades out, a new history card slides in at the top of the list.

### Scene 2: "Browse History" (3 s)

1. Cursor moves to the freshly inserted history card.
2. Card gets a subtle highlight/selection effect (border-color shift, slight elevation).
3. Preview text types in: *"Meeting notes from today's product sync…"*
4. Tags fade in one by one: `meeting`, `product`.

### Scene 3: "Apply Smart Mode" (3 s)

1. Cursor moves to the **Smart** action button on the card.
2. Click animation on the button (depress + color flash).
3. Brief processing indicator (pulsing dot or spinner).
4. Card updates: an `Email` badge appears and the preview text reformats to a more structured layout.

### Scene 4: "Copy Result" (3 s)

1. Cursor moves to the copy button.
2. Click animation (icon swaps to checkmark briefly).
3. A *"Copied!"* toast notification fades in and out.
4. Short pause, then seamless reset to Scene 1.

## Technical Approach

### Option A: Pure CSS (Recommended for v1)

- CSS `@keyframes` for cursor movement (`transform: translate`).
- `animation-delay` for staggered element appearances.
- CSS transitions for card state changes (highlight, badge swap).
- Estimated scope: ~200 lines of CSS.
- **Pro:** No JS dependency, works with SSR, `prefers-reduced-motion` friendly.
- **Con:** Less flexible timing, harder to sync complex multi-element sequences.

### Option B: Lightweight JS + CSS

- `IntersectionObserver` triggers the animation when the mockup enters the viewport.
- JS controls timing via CSS class toggles (add/remove at precise intervals).
- CSS handles all visual transitions.
- **Pro:** Better timing control, animation pauses when not visible, easier to orchestrate.
- **Con:** Slightly more complex, requires JS hydration in Astro.

### Option C: Pre-rendered Video/GIF

- Record the animation via Playwright or screen capture.
- Embed as optimized WebM/MP4 with a poster image fallback.
- **Pro:** Pixel-perfect, zero runtime overhead.
- **Con:** Larger file size, harder to iterate, cannot adapt to dark/light theme.

## Recommendation

**Option A (Pure CSS)** for the initial release:

1. Start with a CSS-only animation that loops continuously.
2. Layer on `IntersectionObserver` (Option B) later for play-on-scroll behavior.
3. Respect `prefers-reduced-motion` by disabling all motion via a media query.

## Implementation Notes

- Animation should only play when the mockup section is in the viewport (initially via CSS `animation-play-state`, later via `IntersectionObserver`).
- Include a `prefers-reduced-motion: reduce` media query that sets `animation: none` on all animated elements.
- Cursor element: an absolute-positioned `<div>` with a custom cursor SVG (pointer style, brand-colored).
- All timing values should use CSS custom properties (`--scene-duration`, `--cursor-speed`, etc.) for easy tuning.
- Consider adding a visible play/pause toggle button for accessibility.
- The animation container needs `overflow: hidden` and a fixed aspect ratio to prevent layout shifts.

## Priority

- **Post-beta:** This animation is planned for a future update after the v1.0.0-beta release.
- Focus on getting the static AppPreviewMockup pixel-perfect first; animation is additive polish.
