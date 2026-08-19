import { expect, test } from '@playwright/test';

/**
 * TextExpansion — the Replacements + Voice Snippets section between
 * AppScreenshots and Privacy. Covers the two-card layout, the locale-correct
 * real screenshot on the Replacements card (incl. the runtime lang-switch
 * sync), the presence of the stylised snippet-picker illustration, and the
 * 390px mobile contract.
 */
test.describe('TextExpansion', () => {
  test('renders two feature cards with the localized replacements screenshot (DE)', async ({
    page,
  }) => {
    await page.goto('/');
    const section = page.locator('#text-expansion');
    await section.scrollIntoViewIfNeeded();
    await expect(section).toBeVisible();

    await expect(section.locator('article.tx-card')).toHaveCount(2);

    // Card 1 carries the REAL app screenshot in the page's locale (the DE
    // landing page ships the DE capture) plus the authenticity chip.
    const shot = section.locator('img[data-shot-en]');
    await expect(shot).toHaveAttribute(
      'src',
      '/screenshots/de/dark/03_voice_shortcuts.webp',
    );
    await expect(section.locator('.tx-chip')).toContainText('App-Screenshot');

    // Card 2 is the snippet-picker illustration: search field + three rows,
    // no <img> (there is no real capture of the transient picker panel).
    const mock = section.locator('.tx-frame--mock');
    await expect(mock).toBeVisible();
    await expect(mock.locator('.tx-row')).toHaveCount(3);
    await expect(mock.locator('img')).toHaveCount(0);
  });

  test('EN landing page shows EN copy and the EN screenshot', async ({
    page,
  }) => {
    await page.goto('/en/');
    const section = page.locator('#text-expansion');
    await section.scrollIntoViewIfNeeded();
    await expect(section).toBeVisible();

    await expect(section).toContainText('Voice Snippets');
    await expect(section).toContainText('Replacements');
    await expect(section.locator('img[data-shot-en]')).toHaveAttribute(
      'src',
      '/screenshots/en/dark/03_voice_shortcuts.webp',
    );
  });

  test('runtime language switch swaps the screenshot and its alt text', async ({
    page,
  }) => {
    await page.goto('/');
    const section = page.locator('#text-expansion');
    await section.scrollIntoViewIfNeeded();

    const shot = section.locator('img[data-shot-en]');
    await expect(shot).toHaveAttribute('src', /\/de\//);

    await page.evaluate(() => {
      document.documentElement.lang = 'en';
    });
    await expect(shot).toHaveAttribute(
      'src',
      '/screenshots/en/dark/03_voice_shortcuts.webp',
    );
    await expect(shot).toHaveAttribute('alt', /Replacements page/);
  });

  test('section stays usable at 390px mobile width', async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await page.goto('/');
    const section = page.locator('#text-expansion');
    await section.scrollIntoViewIfNeeded();
    await expect(section).toBeVisible();

    // Both cards stack; no horizontal page overflow.
    await expect(section.locator('article.tx-card')).toHaveCount(2);
    const overflow = await page.evaluate(
      () =>
        document.documentElement.scrollWidth -
        document.documentElement.clientWidth,
    );
    expect(overflow).toBeLessThanOrEqual(0);
  });
});
