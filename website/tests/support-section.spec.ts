import { expect, test } from '@playwright/test';

// Support: one primary sponsor button, then numbered rows in two groups
// (paying / non-paying help). Store review rows only show on their OS and
// hidden rows do not take a number.
test('two groups of numbered rows, numbering skips hidden rows', async ({ page }) => {
  await page.goto('/en/');
  const section = page.getByTestId('support');
  await expect(section.getByRole('heading', { level: 2 })).toHaveText('An independently developed project');
  await expect(page.getByTestId('support-group-money').locator('.support-row')).toHaveCount(1);
  await expect(page.getByTestId('support-group-free').locator('.support-row')).toHaveCount(4);
  await expect(page.getByTestId('support-star')).toHaveAttribute('href', 'https://github.com/whispaste/whispaste');

  // Computed `content` reports the counter() expression, not its value, so
  // check the mechanism: every visible row carries the counter, and the
  // review row of the other OS is display: none (which skips the counter).
  const rows = await section.locator('.support-row').evaluateAll((items) =>
    items.map((row) => ({
      platform: row.getAttribute('data-platform-btn'),
      shown: getComputedStyle(row).display !== 'none',
      numbered: getComputedStyle(row.querySelector('a')!, '::before').content.startsWith('counter(support-way'),
    })),
  );
  expect(rows.filter((r) => r.shown).every((r) => r.numbered)).toBe(true);
  expect(rows.filter((r) => r.platform && !r.shown).length).toBeGreaterThanOrEqual(1);
});

test('support fits without sideways scroll at 390px', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/');
  await page.getByTestId('support-ways').scrollIntoViewIfNeeded();
  const overflow = await page.evaluate(
    () => document.documentElement.scrollWidth - document.documentElement.clientWidth,
  );
  expect(overflow).toBeLessThanOrEqual(0);
});
