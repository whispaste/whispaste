import { expect, test } from '@playwright/test';

// Every page outside the landing shares one frame: PageHero and the full footer.

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
    test(`${path}: hero and full footer are present`, async ({ page }) => {
      await page.goto(path);
      await expect(page.locator('main h1')).toHaveCount(1);
      await expect(page.locator('.page-hero')).toBeVisible();
      await expect(page.getByTestId('footer-link-license')).toBeAttached();
    });
  }
});

test.describe('long-tail landing pages', () => {
  // D-005: hero, rail and closing panel each offer the store purchase, with
  // the purchase line, and no route to GitHub or the free variant next to it.
  for (const path of ['/gpu-kompatibilitaet/', '/en/use-cases/students/', '/zh/comparison/voice-input-tool-alternatives/']) {
    test(`${path}: hero, rail and closing panel carry the store purchase`, async ({ page }) => {
      await page.setViewportSize({ width: 1440, height: 900 });
      await page.goto(path);
      for (const id of ['lp-hero-buy', 'lp-rail-buy', 'lp-end-buy']) {
        const block = page.getByTestId(id);
        await block.scrollIntoViewIfNeeded();
        await expect(block.locator('a[href*="apps.microsoft.com"], a[href*="apps.apple.com"]').first()).toBeVisible();
        await expect(page.getByTestId(`${id}-store-note`)).toBeAttached();
        const text = (await block.innerText()) ?? '';
        expect(text, id).not.toMatch(/github|free|kostenlos|gratuit|免费/i);
        // Linux has no store; only a Linux visitor sees its AppImage button.
        await expect(block.locator('a[href*="github.com"]:visible')).toHaveCount(0);
      }
    });
  }
});

test.describe('legal pages', () => {
  test('table of contents lists every section and jumps to it', async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 900 });
    await page.goto('/datenschutz/');
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

test.describe('use-case pages reuse the home-page scene photos', () => {
  const PHOTO_PAGES = [
    ['/use-cases/programmierer/', 'developer'],
    ['/en/use-cases/students/', 'students'],
    ['/fr/use-cases/everyday/', 'everyday'],
  ] as const;
  for (const [path, photo] of PHOTO_PAGES) {
    test(`${path}: hero shows the ${photo} photo with an AI label`, async ({ page }) => {
      await page.goto(path);
      const figure = page.getByTestId('lp-photo');
      await expect(figure).toBeVisible();
      await expect(figure.locator('img')).toHaveAttribute('src', `/images/use-cases/${photo}-1200.webp`);
      await expect(figure.locator('figcaption')).not.toBeEmpty();
      expect(await figure.locator('img').evaluate((img: HTMLImageElement) => img.naturalWidth)).toBeGreaterThan(0);
    });
  }

  test('other long-tail pages keep their illustration', async ({ page }) => {
    await page.goto('/gpu-kompatibilitaet/');
    await expect(page.getByTestId('lp-photo')).toHaveCount(0);
  });
});
