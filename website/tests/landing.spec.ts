import { expect, test } from '@playwright/test';

test.beforeEach(async ({ page }) => {
  await page.addInitScript(() => {
    window.localStorage.clear();
  });
});

test('hero CTA contains MS Store badge and GitHub link', async ({ page }) => {
  await page.goto('/');

  await expect(page.getByTestId('hero-cta-store')).toBeVisible();
  await expect(page.getByTestId('hero-cta-store').locator('ms-store-badge')).toHaveCount(1);
  await expect(page.getByTestId('hero-cta-github')).toHaveAttribute(
    'href',
    'https://github.com/whispaste/whispaste/releases/latest',
  );
});

test('language toggle switches the landing page from EN to DE', async ({ page }) => {
  await page.goto('/');

  const heroHeading = page.locator('section h1').first();
  await expect(heroHeading).toContainText('Press. Speak.');
  await page.getByTestId('lang-toggle').click();
  await expect(heroHeading).toContainText('Drücken. Sprechen.');
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

test('download page has Store and GitHub sections', async ({ page }) => {
  await page.goto('/download/');
  await expect(page.locator('main h1').first()).toContainText('Download');
  await expect(page.locator('main h2').first()).toContainText('Microsoft Store');
  await expect(page.locator('[data-i18n="download.github.button"]')).toBeVisible();
});
