import { expect, test } from '@playwright/test';

// The star count is resolved at build time with a cache and a committed floor
// (src/scripts/github-stars.ts), so the pill must always carry a number.
test.describe('nav GitHub pill', () => {
  test('desktop pill links to the repo and shows the star count', async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 900 });
    await page.goto('/');
    const pill = page.getByTestId('nav-github');
    await expect(pill).toBeVisible();
    await expect(pill).toHaveAttribute('href', 'https://github.com/whispaste/whispaste');
    await expect(pill).toHaveAttribute('aria-label', /GitHub/);
    await expect(page.getByTestId('nav-github-count')).toHaveText(/^\s*\d[\d.,]*\s*\S*\s*$/);
  });

  test('the visitor browser never calls the GitHub API', async ({ page }) => {
    const calls: string[] = [];
    page.on('request', (req) => {
      if (req.url().includes('api.github.com')) calls.push(req.url());
    });
    await page.goto('/');
    await page.waitForLoadState('networkidle');
    expect(calls).toEqual([]);
  });
});
