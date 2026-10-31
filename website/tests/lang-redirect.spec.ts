import { expect, test, type Page } from '@playwright/test';

// Browser-language redirect (Layout.astro): a real visitor entering from
// outside lands on their language; crawlers/automation never get redirected,
// and an explicit switcher choice wins over the browser setting.
const REAL_UA =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36';

async function asRealVisitor(page: Page, languages: string[]) {
  await page.addInitScript((langs) => {
    Object.defineProperty(navigator, 'webdriver', { get: () => false });
    Object.defineProperty(navigator, 'languages', { get: () => langs });
    Object.defineProperty(navigator, 'language', { get: () => langs[0] });
  }, languages);
}

test.describe('browser-language redirect', () => {
  test.use({ userAgent: REAL_UA });

  test('a French browser landing on / ends on /fr/', async ({ page }) => {
    await asRealVisitor(page, ['fr-FR', 'en']);
    await page.goto('/');
    await expect(page).toHaveURL(/\/fr\/$/);
    await expect(page.locator('html')).toHaveAttribute('lang', 'fr');
  });

  test('deep links keep their page: /engines/ → /es/engines/ for Spanish', async ({ page }) => {
    await asRealVisitor(page, ['es-AR']);
    await page.goto('/engines/');
    await expect(page.locator('html')).toHaveAttribute('lang', 'es');
    expect(new URL(page.url()).pathname).toMatch(/^\/es\//);
  });

  test('an unsupported browser language falls back to English', async ({ page }) => {
    await asRealVisitor(page, ['pl-PL']);
    await page.goto('/');
    await expect(page).toHaveURL(/\/en\/$/);
  });

  test('a German browser stays on the German root', async ({ page }) => {
    await asRealVisitor(page, ['de-CH', 'en']);
    await page.goto('/');
    await expect(page.locator('html')).toHaveAttribute('lang', 'de');
    expect(new URL(page.url()).pathname).toBe('/');
  });

  test('a saved switcher choice beats the browser language', async ({ page }) => {
    await asRealVisitor(page, ['fr-FR']);
    await page.addInitScript(() => localStorage.setItem('wp-lang', 'de'));
    await page.goto('/en/');
    await expect(page.locator('html')).toHaveAttribute('lang', 'de');
  });

  test('crawlers are never redirected', async ({ browser }) => {
    const ctx = await browser.newContext({
      userAgent: 'Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)',
      locale: 'en-US',
    });
    const page = await ctx.newPage();
    await page.addInitScript(() => Object.defineProperty(navigator, 'webdriver', { get: () => false }));
    await page.goto('/');
    await expect(page.locator('html')).toHaveAttribute('lang', 'de');
    expect(new URL(page.url()).pathname).toBe('/');
    await ctx.close();
  });
});
