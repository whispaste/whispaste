import { expect, test } from '@playwright/test';

// #1914: on a phone the download options come before the "why two ways"
// explanation, and the first store/download button sits within the first
// 1.5 screens.
const LOCALES = ['de', 'en', 'es', 'pt', 'it', 'ru', 'zh', 'fr'] as const;
const path = (l: string) => (l === 'de' ? '/download/' : `/${l}/download/`);

test.use({ viewport: { width: 390, height: 844 } });

for (const locale of LOCALES) {
  test(`${path(locale)}: download options lead on a phone`, async ({ page }) => {
    await page.goto(path(locale));
    const { mainFirst, firstButtonTop } = await page.evaluate(() => {
      const main = document.querySelector('.dl-main')!;
      const rail = document.querySelector('.dl-rail')!;
      const button = [...main.querySelectorAll<HTMLElement>('a[href]')].find((a) => a.offsetParent !== null)!;
      return {
        mainFirst: !!(main.compareDocumentPosition(rail) & Node.DOCUMENT_POSITION_FOLLOWING) &&
          main.getBoundingClientRect().top < rail.getBoundingClientRect().top,
        firstButtonTop: button.getBoundingClientRect().top + scrollY,
      };
    });
    expect(mainFirst).toBe(true);
    expect(firstButtonTop).toBeLessThan(844 * 1.5);
  });
}
