import { expect, test } from '@playwright/test';

/**
 * AC4 — browser parity for the overlay mockup.
 *
 * The recording overlay in the paste demo (AppPasteDemo, step 2) is drawn on
 * a <canvas> by the shared
 * `overlay-mockup` renderer, which mirrors the in-app `OverlayPainter` 1:1.
 * This spec runs under both the `chromium` (Chrome/Edge engine) and `webkit`
 * (Safari engine) projects and asserts each renders the SAME pixels via a
 * single shared snapshot baseline (see `snapshotPathTemplate` in
 * playwright.config.ts — the project name is omitted from the path). If WebKit
 * and Chromium diverged on radius, shadow, gradient, waveform or the progress
 * timeline, one of the two runs would fail against the shared baseline.
 *
 * Determinism: reduced motion makes the renderer draw its frozen frame (the
 * spike-verified 22-bar snapshot, timer 0:07, progress 60%), so the only
 * variable left is the rendering engine. The capsule renders the app's real
 * `OverlayStyleVariant.solid` (2026-08-26) — an opaque `WpColorsDark.
 * frameGradient` fill (navy→violet, `#051A3E`→`#140A2F`), no glass/backdrop
 * effects — so there is nothing theme-dependent left to force either.
 */

test.use({
  // Top-level viewport + deviceScaleFactor override the per-project device
  // presets, so chromium and webkit render the canvas at the SAME pixel size
  // (a prerequisite for comparing them against one shared baseline).
  viewport: { width: 900, height: 700 },
  deviceScaleFactor: 2,
  contextOptions: { reducedMotion: 'reduce' },
});

test('overlay mockup renders identically in WebKit and Chromium', async ({ page }) => {
  await page.goto('/');

  // Under reduced motion the paste demo paints its deterministic frozen
  // frame as soon as the section is on screen.
  const canvas = page.locator('#app-paste-demo .apd-overlay-canvas');
  await canvas.scrollIntoViewIfNeeded();
  await expect(canvas).toBeVisible();
  // The demo scales the canvas to a fluid CSS width, which leaves a
  // fractional CSS height that each engine rounds differently in an element
  // screenshot. Pin it to its backing store at DPR 2 (integral CSS box,
  // 1:1 device pixels) so both engines snapshot the identical box.
  await canvas.evaluate((el: HTMLCanvasElement) => {
    el.style.width = `${el.width / 2}px`;
    el.style.height = `${el.height / 2}px`;
    el.style.maxWidth = 'none';
  });
  // Give the frozen frame a beat to paint before snapshotting.
  await page.waitForTimeout(300);

  await expect(canvas).toHaveScreenshot('overlay-mockup.png', {
    // Linux CI measured ~7% renderer variance on the canvas snapshot (mostly
    // font/text anti-aliasing), consistently across multiple runs (not a
    // one-off flake) - kept at 8% margin post-2026-08-26 solid-fill switch:
    // the 4-stop frameGradient plus the accent border stroke are still real
    // cross-engine antialiasing surface even with the glass sheen/rim/
    // specular layers no longer painted. Still enough to catch actual
    // structural drift: radius, shadow, gradient, waveform, and progress.
    maxDiffPixelRatio: 0.08,
    animations: 'disabled',
  });
});
