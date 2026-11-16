import { expect, test, type Page } from '@playwright/test';

// /yt/ short link for YouTube Shorts (src/pages/yt.astro): forwards to the visitor's
// language home page with the Matomo campaign youtube-short and the language as keyword.

async function withLanguages(page: Page, languages: string[]) {
  await page.addInitScript((langs) => {
    Object.defineProperty(navigator, 'languages', { get: () => langs });
    Object.defineProperty(navigator, 'language', { get: () => langs[0] });
  }, languages);
}

for (const [langs, path, kwd] of [
  [['de-DE', 'en'], '/', 'de'],
  [['fr-FR'], '/fr/', 'fr'],
  [['pl-PL'], '/en/', 'en'],
] as const) {
  test(`/yt/ with ${langs[0]} lands on ${path} tagged as youtube-short`, async ({ page }) => {
    await withLanguages(page, [...langs]);
    await page.goto('/yt/');
    await page.waitForURL((url) => url.pathname === path);
    const url = new URL(page.url());
    expect(url.searchParams.get('mtm_campaign')).toBe('youtube-short');
    expect(url.searchParams.get('mtm_kwd')).toBe(kwd);
  });
}

test('/yt/ honours a saved language switcher choice', async ({ page }) => {
  await withLanguages(page, ['fr-FR']);
  await page.addInitScript(() => localStorage.setItem('wp-lang', 'es'));
  await page.goto('/yt/');
  await page.waitForURL((url) => url.pathname === '/es/');
  expect(new URL(page.url()).searchParams.get('mtm_kwd')).toBe('es');
});

test('/yt/ is not indexable', async ({ request }) => {
  const html = await (await request.get('/yt/')).text();
  expect(html).toContain('noindex');
});
