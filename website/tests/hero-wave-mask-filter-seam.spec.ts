import { expect, test } from '@playwright/test';
import sharp from 'sharp';

// Regression test for a dead-straight hard seam that appeared across the
// hero's parallax "wave" background (Hero.astro, the .hero-wave-blur /
// .hero-wave-mask / .wp-parallax-layer stack) partway down the hero section.
//
// Root cause: `.hero-wave-mask` used to carry BOTH a `mask-image` (the
// radial-gradient hole that keeps the wave logo out from behind the
// headline) AND `filter: blur(28px)` (softening the ribbon SVG's own crisp
// vector edge) on the very same element. Combining `mask-image` and
// `filter` on one element makes Chromium rasterize/composite that element
// as a masked layer and then clip the filter's blur bleed at the mask's own
// soft-edge boundary -- turning the mask's intended 40%->90% fade into a
// dead-straight hard cut exactly at that boundary. Proven live in Chrome
// devtools: toggling `mask-image` off (or blowing the ellipse up to 400%)
// made the seam vanish; restoring the original mask reproduced it;  moving
// ONLY `filter` off `.hero-wave-mask` onto a separate, unmasked parent
// wrapper (`.hero-wave-blur`) -- while leaving the mask in place on
// `.hero-wave-mask` -- also removed it, with no change to mask geometry.
//
// Fix: split the three properties that combine to cause some version of
// this bug -- `filter`, `mask-image`, and the scroll-driven `transform` --
// across three separate, nested elements (`.hero-wave-blur` /
// `.hero-wave-mask` / `.wp-parallax-layer`), each holding exactly one.
//
// This test has two independent layers of proof:
//  1. A structural check: no element combines a non-none `filter` with a
//     non-none `mask-image` anywhere in the hero. This directly encodes the
//     proven causal rule and catches ANY future change that re-merges the
//     two properties onto one element, regardless of viewport or content.
//  2. A pixel check: with everything but the wave-blur/-mask/parallax stack
//     hidden (so no other page content can mask or contaminate the sample),
//     scan a vertical strip through the mask's own box for a hard, sudden
//     jump -- the seam's actual visual signature.

test('hero-wave-mask never combines filter + mask-image on one element', async ({ page }) => {
  await page.goto('/');

  const violations = await page.evaluate(() => {
    const bad: Array<{ tag: string; cls: string; filter: string; mask: string }> = [];
    document.querySelectorAll('section.wp-parallax-scope, section.wp-parallax-scope *').forEach((el) => {
      const cs = getComputedStyle(el);
      const mask = cs.maskImage !== 'none' ? cs.maskImage : (cs as any).webkitMaskImage;
      const filter = cs.filter;
      if (filter && filter !== 'none' && mask && mask !== 'none') {
        bad.push({
          tag: el.tagName,
          cls: (el as HTMLElement).className?.toString() ?? '',
          filter,
          mask,
        });
      }
    });
    return bad;
  });

  expect(violations, JSON.stringify(violations, null, 2)).toEqual([]);
});

test('hero-wave-blur/-mask split is intact and produces no hard seam', async ({ page }) => {
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await page.setViewportSize({ width: 1280, height: 900 });
  await page.goto('/');

  const blur = page.locator('.hero-wave-blur');
  const mask = page.locator('.hero-wave-mask');
  await expect(blur).toBeAttached();
  await expect(mask).toBeAttached();

  const props = await page.evaluate(() => {
    const blurEl = document.querySelector('.hero-wave-blur');
    const maskEl = document.querySelector('.hero-wave-mask');
    const bcs = blurEl ? getComputedStyle(blurEl) : null;
    const mcs = maskEl ? getComputedStyle(maskEl) : null;
    return {
      blurFilter: bcs?.filter,
      blurMask: bcs ? (bcs.maskImage !== 'none' ? bcs.maskImage : (bcs as any).webkitMaskImage) : undefined,
      maskFilter: mcs?.filter,
      maskMask: mcs ? (mcs.maskImage !== 'none' ? mcs.maskImage : (mcs as any).webkitMaskImage) : undefined,
    };
  });

  // The split itself: blur wrapper filters but doesn't mask; mask wrapper
  // masks but doesn't filter.
  expect(props.blurFilter).not.toBe('none');
  expect(props.blurMask === undefined || props.blurMask === 'none').toBeTruthy();
  expect(props.maskFilter).toBe('none');
  expect(props.maskMask).not.toBe('none');

  // Isolate the wave stack visually (hide every other element) so no other
  // hero content can mask or contaminate the sample -- mirrors the manual
  // Chrome-devtools bisection that first found and fixed this bug.
  const geometry = await page.evaluate(() => {
    const style = document.createElement('style');
    style.textContent = `
      body *:not(.hero-wave-blur):not(.hero-wave-blur *) { visibility: hidden !important; }
    `;
    document.head.appendChild(style);
    const el = document.querySelector('.hero-wave-mask') as HTMLElement;
    el.style.setProperty('visibility', 'visible', 'important');
    document.querySelector('.hero-wave-blur')!
      .parentElement!.querySelectorAll('.hero-wave-blur, .hero-wave-blur *')
      .forEach((n) => (n as HTMLElement).style.setProperty('visibility', 'visible', 'important'));
    const rect = el.getBoundingClientRect();
    return {
      docTop: rect.top + window.scrollY,
      docBottom: rect.bottom + window.scrollY,
      left: rect.left,
      width: rect.width,
    };
  });

  // Bring the mask box's bottom half (where the seam appeared) into view.
  const targetScrollY = Math.max(0, Math.round(geometry.docBottom - 900 * 0.6));
  await page.evaluate((y) => window.scrollTo({ top: y, left: 0, behavior: 'instant' }), targetScrollY);
  await page.waitForTimeout(200);

  const sampleX = Math.round(geometry.left + geometry.width * 0.5);
  const screenshotBuffer = await page.screenshot();
  const { data, info } = await sharp(screenshotBuffer).raw().toBuffer({ resolveWithObject: true });
  const { width, height, channels } = info;

  let maxJump = 0;
  let maxY = -1;
  let prev: number[] | null = null;
  for (let y = 0; y < height; y++) {
    const idx = (y * width + sampleX) * channels;
    const c = [data[idx], data[idx + 1], data[idx + 2]];
    if (prev) {
      const d = Math.abs(c[0] - prev[0]) + Math.abs(c[1] - prev[1]) + Math.abs(c[2] - prev[2]);
      if (d > maxJump) {
        maxJump = d;
        maxY = y;
      }
    }
    prev = c;
  }

  // A real fade changes gradually (single-digit deltas between adjacent
  // rows); the seam this test guards against was a one-row jump in the
  // hundreds (e.g. rgb(172,185,204) -> rgb(24,40,89) between two adjacent
  // pixel rows).
  expect(maxJump, `biggest single-row jump was ${maxJump} at y=${maxY} (sampleX=${sampleX})`).toBeLessThan(40);
});
