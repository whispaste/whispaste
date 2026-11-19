import { expect, test } from '@playwright/test';

/**
 * The browser-language redirect (Layout.astro) must keep the visit's real
 * referrer for Matomo: before `location.replace` it stores it in
 * sessionStorage under the shape scripts/referrer-carry.ts reads
 * (`{ ref, to, at }`); the Matomo bootstrap on the target page passes it to
 * `setReferrerUrl`. Matomo itself never runs on 127.0.0.1, so this checks the
 * hand-over; the unit test covers the Matomo side.
 *
 * The redirect skips automation and crawlers, so this test looks like a
 * normal French-speaking browser.
 */
test.use({
  locale: 'fr-FR',
  userAgent:
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36',
});

test('language redirect carries the original referrer to the target page', async ({ page }) => {
  await page.addInitScript(() => {
    Object.defineProperty(navigator, 'webdriver', { get: () => false });
  });
  await page.route('https://matomo.silvio-und-maik.de/**', (route) => route.abort());
  await page.goto('/whisper-desktop/', { referer: 'https://www.google.com/' });
  await expect(page).toHaveURL(/\/fr\/whisper-desktop\/$/);
  const carried = await page.evaluate(() => JSON.parse(sessionStorage.getItem('wp-ref') ?? 'null'));
  expect(carried).toMatchObject({ ref: 'https://www.google.com/', to: '/fr/whisper-desktop/' });
  expect(typeof carried.at).toBe('number');
});

test('the Matomo bootstrap applies the carried referrer before the page view', async ({ page }) => {
  await page.route('https://matomo.silvio-und-maik.de/**', (route) => route.abort());
  await page.goto('/en/whisper-desktop/');
  // Text matching skips <script> content, so read it directly.
  const bootstraps = await page.evaluate(() =>
    [...document.querySelectorAll('script:not([src])')]
      .map((script) => script.textContent ?? '')
      .filter((text) => text.includes('trackPageView')),
  );
  expect(bootstraps).toHaveLength(1);
  const [bootstrap] = bootstraps;
  expect(bootstrap.indexOf('setReferrerUrl')).toBeGreaterThan(-1);
  expect(bootstrap.indexOf('setReferrerUrl')).toBeLessThan(bootstrap.indexOf('trackPageView'));
});
