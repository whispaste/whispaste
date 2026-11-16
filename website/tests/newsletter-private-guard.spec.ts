import { expect, test } from '@playwright/test';

/**
 * Guard for the private newsletter link pages (confirm, unsubscribe, device;
 * all nine languages incl. Hebrew). Their address carries a secret token, so
 * they must stay out of analytics, referrers, indexes and the language switcher,
 * and the token must leave the address bar once the page has read it.
 */

const LANGS = ['', 'en', 'es', 'pt', 'it', 'ru', 'zh', 'fr', 'he'] as const;
const ACTIONS = ['confirm', 'unsubscribe', 'device'] as const;
const TOKEN = 'A'.repeat(43);
const API = 'https://api.whispaste.de/**';

for (const lang of LANGS) {
  for (const action of ACTIONS) {
    const path = `${lang ? `/${lang}` : ''}/newsletter/${action}/`;
    test(`private guard ${path}`, async ({ page }) => {
      const hosts: string[] = [];
      page.on('request', (r) => hosts.push(r.url()));
      await page.goto(`${path}?token=${TOKEN}`);
      await expect(page.getByTestId(`newsletter-${action}-page`)).toBeVisible();

      await expect(page.locator('meta[name="referrer"]')).toHaveAttribute('content', 'no-referrer');
      expect(await page.locator('meta[name="robots"]').getAttribute('content')).toMatch(/noindex/);
      await expect(page.getByTestId('contact-widget')).toHaveCount(0);
      await expect(page.getByTestId('lang-switch')).toHaveCount(0);
      await expect(page.getByTestId('mobile-lang-switch')).toHaveCount(0);

      const html = await page.content();
      expect(html).not.toMatch(/matomo/i);
      expect(html).not.toMatch(/web-?vitals/i);
      expect(hosts.filter((u) => /matomo|sentry\.io|ingest/i.test(u))).toEqual([]);

      await expect.poll(() => page.evaluate(() => location.href)).not.toContain(TOKEN);
    });
  }
}

test('send button keeps focus while the request runs (aria-disabled, not disabled)', async ({ page }) => {
  let release!: () => void;
  const gate = new Promise<void>((r) => (release = r));
  let calls = 0;
  await page.route(API, async (route) => {
    if (route.request().method() === 'OPTIONS') return route.fulfill({ status: 204, headers: { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*' } });
    if (route.request().method() !== 'POST') return route.fulfill({ status: 200, headers: { 'access-control-allow-origin': '*' }, body: '{}' });
    calls += 1;
    await gate;
    await route.fulfill({ status: 200, contentType: 'application/json', headers: { 'access-control-allow-origin': '*' }, body: '{"status":"ok"}' });
  });
  await page.goto(`/en/newsletter/confirm/?token=${TOKEN}`);
  const button = page.getByTestId('newsletter-confirm-button');
  await button.focus();
  await button.click();
  await expect(button).toHaveAttribute('aria-disabled', 'true');
  await expect(button).not.toHaveAttribute('disabled', /.*/);
  await expect(button).toBeFocused();
  await button.click({ force: true });
  release();
  await expect(button).toBeHidden();
  expect(calls).toBe(1);
});
