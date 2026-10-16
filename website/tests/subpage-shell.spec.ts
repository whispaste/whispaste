import { expect, test } from '@playwright/test';

// Every page outside the landing shares one frame: PageHero, the full
// footer with the closing wordmark, no horizontal overflow at 390px.

const SUBPAGES = [
  '/download/',
  '/changelog/',
  '/sponsor/',
  '/screenshots/',
  '/impressum/',
  '/datenschutz/',
  '/en/privacy/',
  '/en/impressum/',
  '/fr/sponsor/',
  '/gpu-kompatibilitaet/',
  '/en/use-cases/programmer/',
] as const;

test.describe('subpage shell', () => {
  for (const path of SUBPAGES) {
    test(`${path}: hero, full footer and no sideways scroll at 390px`, async ({ page }) => {
      await page.setViewportSize({ width: 390, height: 844 });
      await page.goto(path);
      await expect(page.locator('main h1')).toHaveCount(1);
      await expect(page.locator('.page-hero')).toBeVisible();
      await expect(page.getByTestId('footer-link-license')).toBeAttached();
      const overflow = await page.evaluate(
        () => document.documentElement.scrollWidth - document.documentElement.clientWidth,
      );
      expect(overflow).toBeLessThanOrEqual(0);
    });
  }
});

test.describe('long-tail landing pages', () => {
  test('hero CTA, rail and closing CTA point to the same target', async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 900 });
    await page.goto('/gpu-kompatibilitaet/');
    const heroCta = page.getByTestId('lp-hero-cta');
    await expect(heroCta).toBeVisible();
    await expect(page.getByTestId('lp-rail')).toBeVisible();
    const href = await heroCta.getAttribute('href');
    expect(href).toBeTruthy();
    await expect(page.getByTestId('lp-cta').locator('a')).toHaveAttribute('href', href ?? '');
  });
});

test.describe('legal pages', () => {
  test('table of contents lists every section and jumps to it', async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 900 });
    await page.goto('/datenschutz/');
    await expect(page.locator('#pageTitle')).toHaveText('Datenschutzerklärung');
    const content = page.getByTestId('legal-privacy-content');
    const headings = content.locator('h2');
    const links = page.getByTestId('legal-privacy-toc').locator('a');
    const count = await headings.count();
    expect(count).toBeGreaterThan(10);
    await expect(links).toHaveCount(count);
    // Entities must not be escaped twice ("&amp;amp;").
    await expect(links.filter({ hasText: '&amp;' })).toHaveCount(0);

    await links.nth(6).click();
    await expect(page).toHaveURL(/#section-7$/);
    await expect(headings.nth(6)).toBeInViewport();
  });

  test('the imprint renders only the page language', async ({ page }) => {
    await page.goto('/en/impressum/');
    await expect(page.locator('#content-en')).toBeVisible();
    await expect(page.locator('#content-de')).toHaveCount(0);
  });
});

test.describe('FAQ hand-off to the contact widget', () => {
  test('"Ask a question" opens the contact panel', async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 900 });
    await page.goto('/en/');
    await expect(page.getByTestId('contact-panel')).toBeHidden();
    await page.getByTestId('faq-ask-open').click();
    await expect(page.getByTestId('contact-panel')).toBeVisible();
  });
});
