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

  test('the live count from our API replaces the build-time value', async ({ page }) => {
    await page.route('**/v1/github/stars', (route) =>
      route.fulfill({ json: { count: 1234, fetchedAt: '2026-10-16T12:00:00Z' } }),
    );
    await page.setViewportSize({ width: 1440, height: 900 });
    await page.goto('/en/');
    await expect(page.getByTestId('nav-github-count')).toHaveText('1.2K');
    await expect(page.getByTestId('nav-github')).toHaveAttribute('aria-label', /1234/);
  });

  test('an API failure keeps the build-time count', async ({ page }) => {
    await page.route('**/v1/github/stars', (route) => route.fulfill({ status: 503, json: { title: 'Star count unavailable' } }));
    await page.setViewportSize({ width: 1440, height: 900 });
    await page.goto('/en/');
    await page.waitForLoadState('networkidle');
    await expect(page.getByTestId('nav-github-count')).toHaveText(/^\s*\d/);
  });
});
