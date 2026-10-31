import { expect, test } from '@playwright/test';
import { i18n, SUPPORTED_LOCALES, type Locale } from '../src/scripts/i18n.ts';

// Coffee support buttons: on the sponsor page (hero actions) and on the home
// support section, in every locale. Ko-fi and Buy Me a Coffee are equal-rank
// buttons (maintainer decision 6c). The umbrella caption on the home page comes
// from the i18n dictionary. Forbidden donation wording (CONTEXT.md §7) must not
// appear in the rendered text of either page.
const KOFI = 'https://ko-fi.com/silviol';
const BMC = 'https://buymeacoffee.com/silvio.lindstedt';
const FORBIDDEN = /\bspenden?\b|donat|donaci|\bdonar\b|\bdoar\b|doação|\bdonazione|\bdonare\b|\bdon(?!['’])\b|\bun don\b|пожертв|捐助|捐款|捐赠/i;

const prefix = (lang: Locale) => (lang === 'de' ? '' : `/${lang}`);

for (const lang of SUPPORTED_LOCALES) {
  const label = i18n[lang]['coffee.label'];

  test(`${lang}: sponsor page shows Ko-fi and Buy Me a Coffee at equal rank in the hero`, async ({ page }) => {
    await page.goto(`${prefix(lang)}/sponsor/`);
    const kofi = page.getByTestId('sponsor-coffee');
    const bmc = page.getByTestId('sponsor-buy-me-a-coffee');
    await expect(kofi).toBeVisible();
    await expect(kofi).toHaveAttribute('href', KOFI);
    await expect(kofi).toHaveText('Ko-fi');
    await expect(kofi).toHaveAttribute('rel', /noopener/);
    await expect(bmc).toHaveAttribute('href', BMC);
    await expect(bmc).toHaveText('Buy Me a Coffee');
    await expect(bmc).toHaveClass(/wp-coffee-button/);
    await expect(kofi).toHaveClass(/wp-coffee-button/);
    expect(FORBIDDEN.test(await page.locator('body').innerText())).toBe(false);
  });

  test(`${lang}: home support section shows Ko-fi and Buy Me a Coffee at equal rank`, async ({ page }) => {
    await page.goto(`${prefix(lang)}/`);
    const kofi = page.getByTestId('support-coffee');
    await expect(page.getByTestId('support-coffee-group')).toContainText(label);
    await expect(kofi).toHaveAttribute('href', KOFI);
    await expect(kofi).toHaveText('Ko-fi');
    await expect(kofi).toHaveClass(/wp-coffee-button/);
    await expect(page.getByTestId('support-buy-me-a-coffee')).toHaveAttribute('href', BMC);
    await expect(page.getByTestId('support-buy-me-a-coffee')).toHaveText('Buy Me a Coffee');
    await expect(page.getByTestId('support-buy-me-a-coffee')).toHaveClass(/wp-coffee-button/);
    expect(FORBIDDEN.test(await page.getByTestId('support').innerText())).toBe(false);
    expect(FORBIDDEN.test(await page.locator('body').innerText())).toBe(false);
  });
}
