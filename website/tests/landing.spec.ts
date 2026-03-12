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
    '/download/',
  );
});

test('language toggle switches the landing page from EN to DE', async ({ page }) => {
  await page.goto('/');

  await expect(page.locator('h1')).toContainText('Press. Speak.');
  await page.getByTestId('lang-toggle').click();
  await expect(page.locator('h1')).toContainText('Drücken. Sprechen.');
});

test('FAQ section is visible and has accordion items', async ({ page }) => {
  await page.goto('/');

  const faq = page.locator('#faq');
  await faq.scrollIntoViewIfNeeded();
  await expect(faq).toBeVisible();
  await expect(faq.locator('details')).toHaveCount(7);
});

test('legal pages load without 404s', async ({ page }) => {
  await page.goto('/datenschutz/');
  await expect(page.locator('#pageTitle')).toBeVisible();

  await page.goto('/impressum/');
  await expect(page.locator('#pageTitle')).toBeVisible();
});

test('download page loads and contains SmartScreen guide', async ({ page }) => {
  await page.goto('/download/');
  await expect(page.locator('h1')).toContainText('download');
  await expect(page.locator('h2')).toContainText('warning');
});
