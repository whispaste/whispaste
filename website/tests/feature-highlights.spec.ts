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

// The "more" disclosure groups the remaining features by what they do for the
// user (internal-notes), never as one flat feature list.
const MORE_GROUPS = { dictate: 7, text: 4, safe: 3, fit: 3 } as const;

for (const path of ['/', '/en/'] as const) {
  test(`${path}: "more" disclosure shows four titled benefit groups`, async ({ page }) => {
    await page.goto(path);
    await page.getByTestId('features-more-toggle').click();
    for (const [key, count] of Object.entries(MORE_GROUPS)) {
      const group = page.getByTestId(`features-more-${key}`);
      await expect(group.locator('h3')).not.toBeEmpty();
      await expect(group.locator('dt')).toHaveCount(count);
      for (const dd of await group.locator('dd').all()) await expect(dd).not.toBeEmpty();
    }
  });
}
