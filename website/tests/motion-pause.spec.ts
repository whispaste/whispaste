import { expect, test, type Page } from '@playwright/test';

// #1910 (WCAG 2.2.2): an in-page switch stops every endless animation and
// the moving text band, and the choice survives a reload.
const LOCALES = ['de', 'en', 'es', 'pt', 'it', 'ru', 'zh', 'fr'] as const;
const prefix = (l: string) => (l === 'de' ? '/' : `/${l}/`);

const runningEndless = (page: Page) =>
  page.evaluate(
    () =>
      document
        .getAnimations()
        .filter((a) => a.effect?.getTiming().iterations === Infinity && a.playState === 'running').length,
  );

const bandX = (page: Page) =>
  page.locator('[data-tk-track]').evaluate((el) => getComputedStyle(el).transform);

async function scrollThrough(page: Page) {
  const height = await page.evaluate(() => document.documentElement.scrollHeight);
  for (let y = 0; y < height; y += 700) {
    await page.evaluate((top) => window.scrollTo({ top, behavior: 'instant' }), y);
    await page.waitForTimeout(60);
  }
}

test('pause switch stops endless motion and survives a reload', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.goto('/');
  await page.waitForTimeout(800);
  expect(await runningEndless(page)).toBeGreaterThan(0);

  const toggle = page.getByTestId('footer-motion-toggle');
  await toggle.scrollIntoViewIfNeeded();
  await toggle.click();
  await expect(toggle).toHaveAttribute('aria-pressed', 'true');

  await scrollThrough(page);
  expect(await runningEndless(page)).toBe(0);
  await page.locator('[data-testid="text-kinds-marquee"]').scrollIntoViewIfNeeded();
  const before = await bandX(page);
  await page.waitForTimeout(400);
  expect(await bandX(page)).toBe(before);

  await page.reload();
  await expect(page.locator('html')).toHaveAttribute('data-motion', 'paused');
  await expect(page.getByTestId('footer-motion-toggle')).toHaveAttribute('aria-pressed', 'true');
  await page.waitForTimeout(500);
  await scrollThrough(page);
  expect(await runningEndless(page)).toBe(0);

  // Switching back on lets the motion run again.
  await page.getByTestId('footer-motion-toggle').click();
  await expect(page.locator('html')).not.toHaveAttribute('data-motion', 'paused');
  await page.evaluate(() => window.scrollTo({ top: 0, behavior: 'instant' }));
  await page.waitForTimeout(500);
  expect(await runningEndless(page)).toBeGreaterThan(0);
});

for (const locale of LOCALES) {
  test(`${prefix(locale)}: footer carries a labelled pause switch`, async ({ page }) => {
    await page.goto(prefix(locale));
    const toggle = page.getByTestId('footer-motion-toggle');
    await expect(toggle).toHaveAttribute('aria-pressed', 'false');
    expect((await toggle.innerText()).trim().length).toBeGreaterThan(3);
  });
}
