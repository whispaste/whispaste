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
  await expect(languages.locator('img')).toHaveCount(0);
});
