import { expect, test } from '@playwright/test';

test.beforeEach(async ({ page }) => {
  await page.addInitScript(() => {
    window.localStorage.clear();
  });
});

test('hero CTA contains platform download button(s)', async ({ page }) => {
  await page.goto('/');

  // At least one download button must be visible (platform-adaptive: one or both shown)
  const storeBtn = page.getByTestId('store-button').first();
  const appleBtn = page.getByTestId('apple-button').first();
  const storeVisible = await storeBtn.isVisible();
  const appleVisible = await appleBtn.isVisible();
  expect(storeVisible || appleVisible).toBe(true);
});

test('language toggle switches the landing page between DE and EN', async ({ page }) => {
  await page.goto('/');

  const heroHeading = page.locator('section h1').first();
  await expect(heroHeading).toContainText('Drücken. Sprechen.');
  await page.getByTestId('lang-toggle').click();
  await page.waitForURL(/\/en\/?$/);
  await expect(page.locator('section h1').first()).toContainText('Press. Speak.');
});

test('FAQ section is visible and has accordion items', async ({ page }) => {
  await page.goto('/');

  const faq = page.locator('#faq');
  await faq.scrollIntoViewIfNeeded();
  await expect(faq).toBeVisible();
  await expect(faq.locator('details')).toHaveCount(9);
});

test('legal pages load without 404s', async ({ page }) => {
  await page.goto('/datenschutz/');
  await expect(page.locator('#pageTitle')).toBeVisible();

  await page.goto('/impressum/');
  await expect(page.locator('#pageTitle')).toBeVisible();
});

test('download page has Store and GitHub sections', async ({ page }) => {
  await page.goto('/download/');
  await expect(page.locator('main h1').first()).toContainText('WhisPaste herunterladen');
  await expect(page.locator('main h2').first()).toContainText('Microsoft Store');
  // GitHub free download section — Windows button has data-testid="github-windows-button"
  await expect(page.getByTestId('github-windows-button')).toBeVisible();
});

test('hero recording mockup renders the final overlay on a canvas (no privacy badge)', async ({ page }) => {
  await page.goto('/');
  await page.locator('.carousel-dot').nth(1).click();

  // The overlay is now a single canvas drawn 1:1 from the SSOT design spec —
  // not a DOM pill. (Issue 10: website = fourth parity platform.)
  const canvas = page.locator('#overlay-canvas');
  await expect(canvas).toBeVisible();

  // AC2: the privacy badge (anti-vocabulary) is gone from markup entirely.
  await expect(page.locator('.overlay-badge-local')).toHaveCount(0);
  await expect(page.locator('.overlay-badge-ai')).toHaveCount(0);
  await expect(page.locator('.overlay-pill')).toHaveCount(0);
  await expect(page.locator('.overlay-wave-bar')).toHaveCount(0);

  // The canvas actually draws something (non-empty backing store).
  const drawn = await canvas.evaluate((el) => {
    const c = el as HTMLCanvasElement;
    const ctx = c.getContext('2d');
    if (!ctx || c.width === 0 || c.height === 0) return false;
    const { data } = ctx.getImageData(0, 0, c.width, c.height);
    for (let i = 3; i < data.length; i += 4) {
      if (data[i] !== 0) return true; // any non-transparent pixel
    }
    return false;
  });
  expect(drawn).toBe(true);
});
