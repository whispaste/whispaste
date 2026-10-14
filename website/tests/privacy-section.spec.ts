import { expect, test } from '@playwright/test';

// Privacy shows two labelled audio paths (local default, optional cloud), a
// telemetry line and a link to the explainer page.
test('privacy section shows both audio paths and the details link', async ({ page }) => {
  await page.goto('/en/');
  const section = page.getByTestId('privacy');
  await section.scrollIntoViewIfNeeded();
  await expect(page.getByTestId('privacy-path-local')).toContainText('Default');
  await expect(page.getByTestId('privacy-path-local').locator('ol li')).toHaveCount(3);
  await expect(page.getByTestId('privacy-path-cloud')).toContainText('Only if you choose it');
  await expect(page.getByTestId('privacy-details')).toHaveAttribute('href', '/en/privacy-speech-recognition/');
});
