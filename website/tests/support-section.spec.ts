import { expect, test } from '@playwright/test';

// Support: the provider tiles (paying help) and numbered rows for help
// without money. Store review rows only show on their OS.
test('provider tiles and free rows, store rows of the other OS are hidden', async ({ page }) => {
  await page.goto('/en/');
  const section = page.getByTestId('support');
  await expect(page.getByTestId('support-group-money').locator('.wp-support-tile')).toHaveCount(4);
  await expect(page.getByTestId('support-group-free').locator('.support-row')).toHaveCount(4);
  await expect(page.getByTestId('support-star')).toHaveAttribute('href', 'https://github.com/whispaste/whispaste');

  // Platform gating: the review row of the other OS is display: none.
  const rows = await section.locator('.support-row').evaluateAll((items) =>
    items.map((row) => ({
      platform: row.getAttribute('data-platform-btn'),
      shown: getComputedStyle(row).display !== 'none',
    })),
  );
  expect(rows.filter((r) => r.platform && !r.shown).length).toBeGreaterThanOrEqual(1);
});
