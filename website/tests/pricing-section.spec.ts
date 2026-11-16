import { expect, test } from '@playwright/test';

// Pricing: two routes to the same app (store/platform download and free GitHub),
// and one shared list of what both include.
test('two route cards and the shared feature list', async ({ page }) => {
  await page.goto('/en/');
  const section = page.getByTestId('pricing');
  const cards = section.locator('.price-card');
  await expect(cards).toHaveCount(2);
  // The layout script points download links at the visitor's own platform
  // card (#245, #1472), which makes the href absolute with an OS anchor.
  await expect(page.getByTestId('pricing-free')).toHaveAttribute(
    'href',
    /^(https?:\/\/[^/]+)?\/en\/download\/(#(windows|macos|linux))?$/,
  );
  await expect(page.getByTestId('pricing-includes').locator('li')).toHaveCount(8);
});
