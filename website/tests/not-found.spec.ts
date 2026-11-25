import { expect, test } from '@playwright/test';

// #1913: unknown addresses get the site's own 404 page (navigation, home,
// download and FAQ links) in the visitor's language, never indexed.
const LOCALES = ['de', 'en', 'es', 'pt', 'it', 'ru', 'zh', 'fr'] as const;
const prefix = (l: string) => (l === 'de' ? '/' : `/${l}/`);

for (const locale of LOCALES) {
  test(`${prefix(locale)}…: unknown address shows the localized 404 page`, async ({ page }) => {
    const response = await page.goto(`${prefix(locale)}gibt-es-nicht/`);
    expect(response?.status()).toBe(404);
    if (locale !== 'de') await page.waitForURL(`**/${locale}/404/`);

    await expect(page.getByTestId('not-found-hero')).toBeVisible();
    await expect(page.locator('nav').first()).toBeVisible();
    await expect(page.getByTestId('not-found-home')).toHaveAttribute('href', prefix(locale));
    await expect(page.getByTestId('not-found-download')).toHaveAttribute('href', `${prefix(locale)}download/`);
    await expect(page.getByTestId('not-found-faq')).toHaveAttribute('href', `${prefix(locale)}#faq`);
    await expect(page.locator('meta[name="robots"]')).toHaveAttribute('content', /noindex/);
  });
}
