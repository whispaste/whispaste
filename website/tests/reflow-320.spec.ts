import { expect, test } from '@playwright/test';

/**
 * reflow-320.spec.ts — the landing page and /download/ reflow at 320 CSS px
 * in every locale (WCAG 1.4.10, #1845): no horizontal scrolling. Implicit
 * grid columns grew to their widest content (the macOS App Store button, a
 * long German word) and widened the page to 330–375 px.
 */

const LANGS = ['en', 'es', 'pt', 'it', 'fr', 'ru', 'zh'];
const PAGES = [
  { lang: 'de', path: '/' },
  { lang: 'de', path: '/download/' },
  ...LANGS.flatMap((lang) => [
    { lang, path: `/${lang}/` },
    { lang, path: `/${lang}/download/` },
  ]),
];

// The page orders and shows the cards by the visitor's system; the macOS
// card's large App Store button was the one that overflowed.
const SYSTEMS = {
  macos: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0 Safari/537.36',
  windows: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0 Safari/537.36',
  linux: 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0 Safari/537.36',
};

for (const [os, userAgent] of Object.entries(SYSTEMS)) {
  test.describe(os, () => {
    test.use({ viewport: { width: 320, height: 640 }, userAgent });
    for (const { lang, path } of PAGES) {
      test(`${lang} ${path}: fits a 320 px viewport`, async ({ page }) => {
        await page.goto(path);
        await expect(page.locator('html')).toHaveAttribute('data-os', os);
        const width = await page.evaluate(() => document.documentElement.scrollWidth);
        expect(width).toBeLessThanOrEqual(320);
      });
    }
  });
}
