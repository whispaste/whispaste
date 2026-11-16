import { expect, test } from '@playwright/test';

/**
 * download-store-recommendation.spec.ts — the Windows direct download is not
 * code-signed, so /download/ recommends the Microsoft Store. The page describes
 * SmartScreen and Smart App Control as hedged possibilities ("may", "can"),
 * never as absolute facts (no "always", "every version", "not even through
 * Run anyway"). Per language, the spec asserts a hedge marker is present and
 * the absolute phrases are absent.
 */

const PAGES = [
  { lang: 'de', path: '/download/' },
  ...['en', 'es', 'pt', 'it', 'fr', 'ru', 'zh'].map((lang) => ({
    lang,
    path: `/${lang}/download/`,
  })),
];

const WORDING: Record<string, { hedge: RegExp; forbidden: string[] }> = {
  de: {
    hedge: /kann|womöglich|je nach/,
    forbidden: ['gar nicht', 'auch nicht über', 'den installer ganz', 'jede neue version', 'jeder version', 'ohne warnung'],
  },
  en: {
    hedge: /\bcan\b|\bmay\b|might/,
    forbidden: ['at all', 'not even through', 'every new version', 'every version', 'each new version', 'without any warning', 'no warning', 'completely', 'has no warning'],
  },
  es: {
    hedge: /puede/,
    forbidden: ['ni siquiera', 'no deja iniciar', 'cada nueva versión', 'cada versión', 'sin ningún aviso', 'sin aviso', 'sin bloqueo', 'por completo'],
  },
  pt: {
    hedge: /pode/,
    forbidden: ['nem mesmo', 'não deixa', 'cada nova versão', 'cada versão', 'sem nenhum aviso', 'sem aviso', 'sem bloqueio', 'por completo'],
  },
  it: {
    hedge: /può|potrebbe/,
    forbidden: ['nemmeno', 'non avvia affatto', 'ogni nuova versione', 'ogni versione', 'senza avvisi', 'nessun avviso', 'nessun blocco', 'del tutto'],
  },
  ru: {
    hedge: /может/,
    forbidden: ['даже через', 'вообще не запустит', 'каждую новую версию', 'каждой версии', 'каждая версия', 'без предупреждений', 'полностью блокирует', 'без блокировки'],
  },
  zh: {
    hedge: /可能/,
    forbidden: ['根本不会', '也不行', '每个新版本', '每个版本', '没有任何警告', '没有安全警告', '完全阻止', '不会被'],
  },
  fr: {
    hedge: /peut/,
    forbidden: ['même via', 'refuse de lancer', 'chaque nouvelle version', 'chaque version', 'aucune alerte', 'aucun avertissement', 'aucun blocage'],
  },
};

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

  test(`${lang}: SmartScreen and Smart App Control claims are hedged, not absolute`, async ({
    page,
  }) => {
    await page.goto(path);
    const { hedge, forbidden } = WORDING[lang];

    const texts = [
      (await page.getByTestId('download-sac-note').textContent()) ?? '',
      (await page.locator('[data-i18n="download.store.desc"]').textContent()) ?? '',
      (await page.locator('[data-i18n="download.trust.desc"]').textContent()) ?? '',
    ];
    for (const text of texts) {
      expect(text.toLowerCase()).toMatch(hedge);
      for (const phrase of forbidden) {
        expect(text.toLowerCase(), `absolute phrase "${phrase}"`).not.toContain(phrase);
      }
    }

    // Structured data (FAQ answer, schema) must not repeat the absolute phrases.
    const jsonLd = await page
      .locator('script[type="application/ld+json"]')
      .evaluateAll((nodes) => nodes.map((node) => node.textContent ?? '').join('\n'));
    expect(jsonLd.length).toBeGreaterThan(0);
    for (const phrase of forbidden) {
      expect(jsonLd.toLowerCase(), `absolute phrase "${phrase}" in JSON-LD`).not.toContain(phrase);
    }
  });
}

test('the trust text and the FAQ never claim the direct download is signed', async ({ page }) => {
  await page.goto('/en/download/');
  const trust = page.locator('[data-i18n="download.trust.desc"]');
  await expect(trust).toContainText('not signed');
  await expect(trust).toContainText('Microsoft Store');
});
