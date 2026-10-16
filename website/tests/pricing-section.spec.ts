import { expect, test } from '@playwright/test';

// Pricing: two routes to the same app (recommended store/platform download
// first, free GitHub second), each with its label, and one shared list of
// what both include.
test('two route cards in order, shared features below', async ({ page }) => {
  await page.goto('/en/');
  const section = page.getByTestId('pricing');
  const cards = section.locator('.price-card');
  await expect(cards).toHaveCount(2);
  await expect(cards.nth(0)).toHaveAttribute('data-testid', 'pricing-get');
  await expect(cards.nth(1)).toHaveAttribute('data-testid', 'pricing-free-card');
  await expect(page.getByTestId('pricing-get').locator('.price-tag')).toHaveText('Recommended');
  await expect(page.getByTestId('pricing-free-card').locator('.price-tag')).toHaveText('Free');
  await expect(page.getByTestId('pricing-free')).toHaveAttribute('href', '/en/download/');
  await expect(page.getByTestId('pricing-includes').locator('li')).toHaveCount(8);
});

test('pricing fits without sideways scroll at 390px', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/');
  await page.getByTestId('pricing-includes').scrollIntoViewIfNeeded();
  const overflow = await page.evaluate(
    () => document.documentElement.scrollWidth - document.documentElement.clientWidth,
  );
  expect(overflow).toBeLessThanOrEqual(0);
});
