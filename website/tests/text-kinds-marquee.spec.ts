import { test, expect } from '@playwright/test';

// The text-kinds band under the hero: empty text fields glide past the
// recording pill and get their text once they have passed it. Every kind is
// announced once (the moving band is aria-hidden), it sits in the story
// order, it never causes horizontal overflow, and it stands still for
// reduced-motion users with every field filled.
for (const path of ['/', '/en/', '/zh/'] as const) {
  test(`${path}: text-kinds band renders localized items once for assistive tech`, async ({ page }) => {
    await page.goto(path);
    const band = page.getByTestId('text-kinds-marquee');
    await expect(band).toHaveAttribute('role', 'region');
    await expect(band).toHaveAttribute('aria-label', /.+/);
    await expect(band.locator('ul li')).toHaveCount(10);
    await expect(band.locator('.tk-stage')).toHaveAttribute('aria-hidden', 'true');
  });
}

test('text-kinds band stands still under reduced motion', async ({ page }) => {
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await page.goto('/');
  const band = page.getByTestId('text-kinds-marquee');
  await band.scrollIntoViewIfNeeded();
  await expect(band).not.toHaveAttribute('data-js', /.*/);
  const x0 = await band.locator('[data-tk-field]').first().evaluate((el) => el.getBoundingClientRect().left);
  await page.waitForTimeout(500);
  const x1 = await band.locator('[data-tk-field]').first().evaluate((el) => el.getBoundingClientRect().left);
  expect(x1).toBe(x0);
  await expect(band.locator('.tk-field__value').first()).toBeVisible();
});
