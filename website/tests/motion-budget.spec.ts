import { expect, test } from '@playwright/test';

// Safari memory (2026-10-16): no live blur filters, and endless decorative
// animations only run in sections that are on screen (motion-budget.ts).
test.describe('motion budget', () => {
  test('no element on the home page carries a blur filter', async ({ page }) => {
    await page.goto('/');
    await page.waitForTimeout(1500);
    const blurred = await page.evaluate(() =>
      [...document.querySelectorAll('*')]
        .filter((el) => /blur\(/.test(getComputedStyle(el).filter + getComputedStyle(el).backdropFilter))
        .map((el) => el.className.toString().slice(0, 40)),
    );
    expect(blurred).toEqual([]);
  });

  test('endless animations below the fold are paused', async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 900 });
    await page.goto('/');
    await page.waitForTimeout(1500);
    const { running, paused } = await page.evaluate(() => {
      const endless = document.getAnimations().filter((a) => a.effect?.getTiming().iterations === Infinity);
      const offscreen = endless.filter((a) => {
        const target = (a.effect as KeyframeEffect | null)?.target;
        return target && target.getBoundingClientRect().top > innerHeight + 400;
      });
      return {
        running: offscreen.filter((a) => a.playState === 'running').length,
        paused: offscreen.filter((a) => a.playState === 'paused').length,
      };
    });
    expect(paused).toBeGreaterThan(0);
    expect(running).toBe(0);
  });
});
