import { expect, test } from '@playwright/test';
import { i18n, SUPPORTED_LOCALES, type Locale } from '../src/scripts/i18n.ts';
import { SUPPORT_PROVIDERS } from '../src/data/support-links.ts';

// Support provider tiles (#398, sponsoring guide): on the home support section
// and on the sponsor page, in every locale, the four providers in guide order
// (PayPal, Ko-fi, Buy Me a Coffee, GitHub Sponsors). Each tile hands over to
// exactly its provider URL in a new tab, carries its local logo, and its
// accessible name is the translated call to action. Forbidden donation
// wording (internal-notes §7) must not appear in the rendered text.
const FORBIDDEN = /\bspenden?\b|donat|donaci|\bdonar\b|\bdoar\b|doação|\bdonazione|\bdonare\b|\bdon(?!['’])\b|\bun don\b|пожертв|捐助|捐款|捐赠/i;

const prefix = (lang: Locale) => (lang === 'de' ? '' : `/${lang}`);

for (const lang of SUPPORTED_LOCALES) {
  for (const [surface, path] of [
    ['support', '/'],
    ['sponsor', '/sponsor/'],
  ] as const) {
    test(`${lang}: ${surface} tiles hand over to each provider`, async ({ page }) => {
      await page.goto(`${prefix(lang)}${path}`);
      const ids: string[] = [];
      for (const provider of SUPPORT_PROVIDERS) {
        const testid = `${surface}-${provider.id}`;
        ids.push(testid);
        const tile = page.getByTestId(testid);
        await expect(tile).toBeVisible();
        await expect(tile).toHaveAttribute('href', provider.href);
        await expect(tile).toHaveAttribute('target', '_blank');
        await expect(tile).toHaveAttribute('rel', /noopener/);
        await expect(tile).toHaveAccessibleName(i18n[lang][`sponsor.${provider.id}.cta`]);
        await expect(tile).toContainText(provider.name);
        await expect(tile.locator('.wp-support-tile__logo svg')).toHaveCount(1);
      }
      const order = await page
        .locator(`[data-testid^="${surface}-"].wp-support-tile`)
        .evaluateAll((tiles) => tiles.map((tile) => tile.getAttribute('data-testid')));
      expect(order).toEqual(ids);
      expect(FORBIDDEN.test(await page.locator('body').innerText())).toBe(false);
    });
  }
}
