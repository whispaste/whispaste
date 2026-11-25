import { expect, test } from '@playwright/test';

// #1912 (WCAG 1.4.1): links inside the download page's running text are
// underlined, not told apart by colour alone, and the diagnose mail hint keeps
// a space before the address.
const LOCALES = ['de', 'en', 'es', 'pt', 'it', 'ru', 'zh', 'fr'] as const;
const path = (l: string) => (l === 'de' ? '/download/' : `/${l}/download/`);

for (const locale of LOCALES) {
  test(`${path(locale)}: inline links in paragraphs are underlined`, async ({ page }) => {
    await page.goto(path(locale));
    const plain = await page.locator('main p a').evaluateAll((links) =>
      links
        .filter((a) => !getComputedStyle(a).textDecorationLine.includes('underline'))
        .map((a) => a.outerHTML.slice(0, 80)),
    );
    expect(plain).toEqual([]);

    const mail = page.locator('main a[href*="Diagnose-Report"]');
    const sentence = await mail.evaluate((a) => a.parentElement!.textContent!.replace(/\s+/g, ' ').trim());
    const address = (await mail.textContent())!.trim();
    expect(sentence.endsWith(` ${address}`)).toBe(true);
  });
}
