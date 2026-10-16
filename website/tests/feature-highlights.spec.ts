import { expect, test } from '@playwright/test';

// FeatureHighlights is one bento grid: Smart Mode as the wide tile, then
// Snippets and three everyday features, each small tile with one abstract
// product fragment that assistive tech skips.

const TILES = ['smartmode', 'snippets', 'editSelection', 'history', 'notes'] as const;

for (const path of ['/', '/en/', '/zh/'] as const) {
  test(`${path}: features bento shows all five tiles with titles`, async ({ page }) => {
    await page.goto(path);
    for (const key of TILES) {
      const tile = page.getByTestId(`features-${key}`);
      await expect(tile).toBeVisible();
      await expect(tile.locator('h3')).not.toBeEmpty();
    }
    await expect(page.locator('#features .fh-frag[aria-hidden="true"]')).toHaveCount(3);
  });
}

test('Smart Mode spans the wide column on desktop', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.goto('/');
  const smart = await page.getByTestId('features-smartmode').boundingBox();
  const snippets = await page.getByTestId('features-snippets').boundingBox();
  expect(smart && snippets).toBeTruthy();
  if (!smart || !snippets) return;
  // Same row, Smart Mode twice as wide.
  expect(Math.abs(smart.y - snippets.y)).toBeLessThan(2);
  expect(smart.width / snippets.width).toBeGreaterThan(1.8);
});

test('features bento stacks without sideways scroll at 390px', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/');
  await page.locator('#features').scrollIntoViewIfNeeded();
  const overflow = await page.evaluate(
    () => document.documentElement.scrollWidth - document.documentElement.clientWidth,
  );
  expect(overflow).toBeLessThanOrEqual(0);
});
