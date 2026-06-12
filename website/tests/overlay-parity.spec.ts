import { expect, test } from '@playwright/test';

/**
 * AC4 — browser parity for the overlay mockup.
 *
 * The recording overlay on the hero is drawn on a <canvas> by the shared
 * `overlay-mockup` renderer, which mirrors the in-app `OverlayPainter` 1:1.
 * This spec runs under both the `chromium` (Chrome/Edge engine) and `webkit`
 * (Safari engine) projects and asserts each renders the SAME pixels via a
 * single shared snapshot baseline (see `snapshotPathTemplate` in
 * playwright.config.ts — the project name is omitted from the path). If WebKit
 * and Chromium diverged on radius, shadow, gradient, waveform or the progress
 * timeline, one of the two runs would fail against the shared baseline.
 *
 * Determinism: reduced motion + a forced light theme make the renderer draw its
 * frozen frame (the spike-verified 22-bar snapshot, timer 0:07, progress 60%),
 * so the only variable left is the rendering engine.
 */

// Force the canonical V4 light theme before any page script runs, so the
// capsule shows the #F7FAFD→#E6EEF5 tint named in the design spec.
test.use({
  colorScheme: 'light',
  // Top-level viewport + deviceScaleFactor override the per-project device
  // presets, so chromium and webkit render the canvas at the SAME pixel size
  // (a prerequisite for comparing them against one shared baseline).
  viewport: { width: 900, height: 700 },
  deviceScaleFactor: 2,
  contextOptions: { reducedMotion: 'reduce' },
});

test.beforeEach(async ({ page }) => {
  await page.addInitScript(() => {
    window.localStorage.setItem('whispaste-theme', 'light');
  });
});

test('overlay mockup renders identically in WebKit and Chromium', async ({ page }) => {
  await page.goto('/');

  // Show scene 2 (the recording overlay). Under reduced motion the carousel
  // does not auto-advance, so click the second dot to reveal it; the renderer
  // then paints its deterministic frozen frame.
  await page.locator('.carousel-dot').nth(1).click();

  const canvas = page.locator('#overlay-canvas');
  await expect(canvas).toBeVisible();
  // Give the frozen frame a beat to paint before snapshotting.
  await page.waitForTimeout(300);

  await expect(canvas).toHaveScreenshot('overlay-mockup.png', {
    // The parity spike measured ~1.55% cross-engine deviation (system-font
    // text anti-aliasing). 2% keeps a small margin while still catching any
    // structural engine break.
    maxDiffPixelRatio: 0.02,
    animations: 'disabled',
  });
});
