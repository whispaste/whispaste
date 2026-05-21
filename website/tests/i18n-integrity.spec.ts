import { expect, test } from '@playwright/test';
import { i18n } from '../src/scripts/i18n.ts';

/**
 * Curated list of ASCII-digraph patterns that are NEVER valid in modern German.
 * These indicate an AI model outputting "ue" instead of "ü", etc.
 * We don't blanket-scan for ae/oe/ue because many legitimate German words
 * contain those sequences (Israel, Poet, Duell, Aero, etc.).
 */
const BROKEN_UMLAUT_PATTERNS: RegExp[] = [
  /\bfuer\b/i,
  /\bueber\b/i,
  /\bzurueck\b/i,
  /\bkuerzel\b/i,
  /\bwuerden?\b/i,
  /\bmuessen\b/i,
  /\bkoennen\b/i,
  /\bfuenf\b/i,
  /\bfuegen?\b/i,
  /\bgruess/i,
  /\bpruef/i,
  /\bwuensch/i,
  /\bbuero\b/i,
  /\boeffn/i,
  /\bkoennt/i,
  /\bmoecht/i,
  /\btaeglich\b/i,
  /\bwaehle?\b/i,
  /\bhaette\b/i,
  /\bhaehnchen\b/i,
  /\bmaessig\b/i,
  /\baendern?\b/i,
  /\bstrasse\b/i,
  /\bgroesse\b/i,
  /\bschliessen\b/i,
  /\bheiss\b/i,
];

/**
 * Detects mojibake — UTF-8 bytes misinterpreted as Latin-1/Windows-1252.
 * These sequences are never valid in any language and indicate encoding
 * corruption at the file or pipeline level.
 */
const MOJIBAKE_PATTERNS: RegExp[] = [
  /Ã¤/, // ä
  /Ã¶/, // ö
  /Ã¼/, // ü
  /ÃŸ/, // ß
  /Ã„/, // Ä
  /Ã–/, // Ö
  /Ãœ/, // Ü
  /â€"/, // —
  /â€œ/, // "
  /â€\u009d/, // "
  /â€™/, // '
  /ï»¿/, // BOM as mojibake
  /�/, // Unicode replacement character
];

const GERMAN_CHARS = /[üöäßÜÖÄ]/;

test.describe('i18n integrity', () => {
  const en = i18n['en']!;
  const de = i18n['de']!;

  test('every EN key has a DE translation', () => {
    const missingInDe = Object.keys(en).filter((key) => !(key in de));
    expect(missingInDe, `Missing DE keys: ${missingInDe.join(', ')}`).toEqual(
      [],
    );
  });

  test('every DE key has an EN translation', () => {
    const missingInEn = Object.keys(de).filter((key) => !(key in en));
    expect(missingInEn, `Missing EN keys: ${missingInEn.join(', ')}`).toEqual(
      [],
    );
  });

  test('DE translations contain actual umlaut characters', () => {
    const allDeText = Object.values(de).join(' ');
    expect(GERMAN_CHARS.test(allDeText)).toBe(true);
  });

  test('DE translations have no broken ASCII-digraph umlauts', () => {
    const violations: string[] = [];

    for (const [key, value] of Object.entries(de)) {
      for (const pattern of BROKEN_UMLAUT_PATTERNS) {
        const match = value.match(pattern);
        if (match) {
          violations.push(`"${key}": found "${match[0]}" in "${value}"`);
        }
      }
    }

    expect(violations).toEqual([]);
  });

  test('DE translations have no mojibake encoding corruption', () => {
    const violations: string[] = [];

    for (const [key, value] of Object.entries(de)) {
      for (const pattern of MOJIBAKE_PATTERNS) {
        const match = value.match(pattern);
        if (match) {
          violations.push(`"${key}": found mojibake "${match[0]}" in "${value}"`);
        }
      }
    }

    expect(violations).toEqual([]);
  });

  test('EN translations have no empty values', () => {
    const empty = Object.entries(en)
      .filter(([, v]) => v.trim() === '')
      .map(([k]) => k);
    expect(empty, `Empty EN values: ${empty.join(', ')}`).toEqual([]);
  });

  test('DE translations have no empty values', () => {
    const empty = Object.entries(de)
      .filter(([, v]) => v.trim() === '')
      .map(([k]) => k);
    expect(empty, `Empty DE values: ${empty.join(', ')}`).toEqual([]);
  });
});

test.describe('screenshot section', () => {
  test('landing teaser is visible and has 2 hero images', async ({ page }) => {
    await page.goto('/');

    const section = page.locator('#app-screenshots');
    await section.scrollIntoViewIfNeeded();
    await expect(section).toBeVisible();

    const images = section.locator('img');
    await expect(images).toHaveCount(2);
  });

  test('screenshot images match the URL locale (DE on /, EN on /en/)', async ({
    page,
  }) => {
    // After Slice 03 (Astro i18n routing) the landing page is German at `/`
    // and English at `/en/`. The client-side `syncScreenshots()` reads
    // `document.documentElement.lang`, which the server now sets correctly
    // per URL, so screenshots are locale-matched without a runtime toggle.
    await page.goto('/');
    const firstImgDe = page.locator('#app-screenshots img').first();
    await expect(firstImgDe).toHaveAttribute('src', /\/de\//);

    await page.goto('/en/');
    const firstImgEn = page.locator('#app-screenshots img').first();
    await expect(firstImgEn).toHaveAttribute('src', /\/en\//);
  });

  test('"See all" link points to gallery page', async ({ page }) => {
    await page.goto('/');
    const link = page.locator('#app-screenshots a[href="/screenshots"]');
    await expect(link).toBeVisible();
  });
});

test.describe('gallery page', () => {
  test('gallery page loads with 5 screenshots', async ({ page }) => {
    await page.goto('/screenshots');
    const items = page.locator('.gallery-item');
    await expect(items).toHaveCount(5);
  });

  test('clicking a thumbnail opens the lightbox', async ({ page }) => {
    await page.goto('/screenshots');
    const firstThumb = page.locator('.gallery-thumb-btn').first();
    await firstThumb.click();
    const lightbox = page.locator('#screenshot-lightbox');
    await expect(lightbox).toHaveAttribute('data-open', '');
    const counter = page.locator('#lightbox-counter');
    await expect(counter).toHaveText('1 / 5');
  });

  test('gallery theme toggle swaps images', async ({ page }) => {
    await page.goto('/screenshots');
    const firstImg = page.locator('.gallery-image').first();
    await expect(firstImg).toHaveAttribute('src', /\/dark\//);

    await page.locator('[data-gallery-theme="light"]').click();
    await expect(firstImg).toHaveAttribute('src', /\/light\//);
  });
});
