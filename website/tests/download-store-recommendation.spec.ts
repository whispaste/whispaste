import { expect, test } from '@playwright/test';

/**
 * download-store-recommendation.spec.ts — the Windows direct download is not
 * code-signed, so /download/ recommends the Microsoft Store and says why:
 * Smart App Control blocks an unsigned installer outright (no "Run anyway"),
 * and SmartScreen warns on every new version.
 */

const PAGES = [
  { lang: 'de', path: '/download/' },
  ...['en', 'es', 'pt', 'it', 'fr', 'ru', 'zh'].map((lang) => ({
    lang,
    path: `/${lang}/download/`,
  })),
];

for (const { lang, path } of PAGES) {
  test(`${lang}: Store card, GitHub card and SmartScreen box explain Smart App Control`, async ({
    page,
  }) => {
    await page.goto(path);

    const storeCard = page.locator('[data-i18n="download.store.desc"]');
    await expect(storeCard).toContainText('Smart App Control');
    await expect(page.locator('[data-i18n="download.store.benefit2"]')).toContainText(
      lang === 'zh' ? '智能应用控制' : 'Smart App Control',
    );

    await expect(page.getByTestId('download-github-unsigned')).toBeVisible();

    // The SmartScreen box is collapsed by default; the note sits inside.
    await page.getByTestId('download-smartscreen-box').locator('summary').click();
    await expect(page.getByTestId('download-sac-note')).toContainText('Smart App Control');
    const link = page.getByTestId('download-sac-store-link');
    await expect(link).toBeVisible();
    await expect(link).toHaveAttribute('href', /^https:\/\/apps\.microsoft\.com\/detail\//);
    await expect(link).toHaveAttribute('rel', 'noopener');
  });
}

test('the trust text and the FAQ never claim the direct download is signed', async ({ page }) => {
  await page.goto('/en/download/');
  const trust = page.locator('[data-i18n="download.trust.desc"]');
  await expect(trust).toContainText('not signed');
  await expect(trust).toContainText('Microsoft Store');
});
