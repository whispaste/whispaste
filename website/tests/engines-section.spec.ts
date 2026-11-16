import { expect, test } from '@playwright/test';

// Engines compares both engines row by row and carries the languages summary
// (#languages, target of the nav link) right below.
test('engines cards share identical rows and #languages resolves', async ({ page }) => {
  await page.goto('/en/');
  const whisperRows = page.getByTestId('engines-whisper').locator('dt');
  const parakeetRows = page.getByTestId('engines-parakeet').locator('dt');
  await expect(whisperRows).toHaveCount(3);
  expect(await parakeetRows.allTextContents()).toEqual(await whisperRows.allTextContents());
  await expect(page.getByTestId('engines-compare')).toHaveAttribute('href', '/en/engines/');
  await expect(page.getByTestId('engines-benchmarks')).toHaveAttribute('href', '/en/engine-benchmarks/');

  const languages = page.locator('#languages');
  await expect(languages).toHaveCount(1);
  await expect(languages).toContainText('99');
});

// The language grid: one tile per Whisper language, names in the page language
// for hover and screen readers.
test('language grid shows 99 tiles with names and the legend counts', async ({ page }) => {
  await page.goto('/');
  const grid = page.getByTestId('languages-grid');
  await expect(grid.locator('li')).toHaveCount(99);
  const de = grid.locator('li[data-code="de"]');
  await expect(de).toHaveAttribute('title', 'Deutsch');
  await expect(grid.locator('li[data-code="ja"]')).toHaveAttribute('title', 'Japanisch');
  await expect(page.getByTestId('languages-legend')).toContainText('99');
  await expect(page.getByTestId('languages-legend')).toContainText('25');
});

test('language names follow the page locale', async ({ page }) => {
  await page.goto('/fr/');
  await expect(page.getByTestId('languages-grid').locator('li[data-code="de"]')).toHaveAttribute('title', 'allemand');
});
