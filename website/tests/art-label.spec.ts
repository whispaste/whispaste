import { expect, test } from '@playwright/test';

// The decorative stage label (aria-hidden, drawn by CSS from data-label) must
// follow the page language. CSS uppercases it; the attribute holds the upper-case word.
const CASES = [
  { path: '/whisper-desktop/', label: 'PLATTFORMEN' },
  { path: '/gpu-kompatibilitaet/', label: 'HARDWARE' },
  { path: '/en/whisper-desktop/', label: 'PLATFORMS' },
  { path: '/es/whisper-desktop/', label: 'PLATAFORMAS' },
  { path: '/changelog/', label: 'VERSIONEN' },
  { path: '/sponsor/', label: 'COMMUNITY' },
] as const;

test.describe('art stage label follows the page language', () => {
  for (const { path, label } of CASES) {
    test(`${path}: label is ${label}`, async ({ page }) => {
      await page.goto(path);
      await expect(page.locator('.page-hero .wp-panel')).toHaveAttribute('data-label', label);
    });
  }
});
