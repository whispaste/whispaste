import { expect, test } from '@playwright/test';

test('capture homepage screenshot section', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 });
  await page.goto('/');
  await page.waitForTimeout(500);
  const section = page.locator('#app-screenshots');
  await section.scrollIntoViewIfNeeded();
  await page.waitForTimeout(300);
  await section.screenshot({ path: 'test-results/homepage-screenshots-section.png' });
});

test('capture gallery page', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 });
  await page.goto('/screenshots');
  await page.waitForTimeout(500);
  await page.screenshot({ path: 'test-results/gallery-page-full.png', fullPage: true });
});

test('capture gallery lightbox', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 });
  await page.goto('/screenshots');
  await page.waitForTimeout(500);
  await page.locator('.gallery-thumb-btn').first().click();
  await page.waitForTimeout(400);
  await page.screenshot({ path: 'test-results/gallery-lightbox.png' });
});
