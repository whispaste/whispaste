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
  test('screenshot section is visible and has images', async ({ page }) => {
    await page.goto('/');

    const section = page.locator('#app-screenshots');
    await section.scrollIntoViewIfNeeded();
    await expect(section).toBeVisible();

    const images = section.locator('img');
    await expect(images).toHaveCount(5);
  });

  test('screenshot images swap when language is toggled', async ({ page }) => {
    await page.goto('/');

    const firstImg = page.locator('#app-screenshots img').first();
    const enSrc = await firstImg.getAttribute('src');
    expect(enSrc).toContain('/en/');

    await page.getByTestId('lang-toggle').click();
    await expect(firstImg).toHaveAttribute('src', /\/de\//);
  });
});
