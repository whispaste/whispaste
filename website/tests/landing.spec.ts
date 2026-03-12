import { expect, test } from '@playwright/test';

test.beforeEach(async ({ page }) => {
  await page.addInitScript(() => {
    window.localStorage.clear();
  });
});

test('hero CTA points to the latest GitHub release', async ({ page }) => {
  await page.goto('/');

  await expect(page.getByTestId('hero-cta-store')).toHaveAttribute(
    'href',
    'https://github.com/whispaste/whispaste/releases/latest',
  );
});

test('language toggle switches the landing page from EN to DE', async ({ page }) => {
  await page.goto('/');

  await expect(page.locator('h1')).toContainText('Speak naturally.');
  await page.getByTestId('lang-toggle').click();
  await expect(page.locator('h1')).toContainText('Natürlich sprechen.');
  await expect(page.locator('[data-i18n="features.label"]')).toHaveText('Warum WhisPaste');
});

test('legal pages load without 404s', async ({ page }) => {
  await page.goto('/datenschutz/');
  await expect(page.locator('#pageTitle')).toBeVisible();

  await page.goto('/impressum/');
  await expect(page.locator('#pageTitle')).toBeVisible();
});
