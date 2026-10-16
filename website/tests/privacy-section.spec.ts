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

// The routes draw a "your computer" boundary: on the local path every step is
// inside it, on the cloud path the provider sits outside (second column).
test('cloud provider sits outside the device boundary, local steps inside', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.goto('/');
  const localOl = page.getByTestId('privacy-path-local').locator('ol');
  await expect(localOl).toHaveAttribute('data-device-label', 'Dein Rechner');
  const cloud = page.getByTestId('privacy-path-cloud').locator('ol li');
  const [mic, provider] = await Promise.all([cloud.nth(0).boundingBox(), cloud.nth(1).boundingBox()]);
  expect(mic && provider).toBeTruthy();
  if (!mic || !provider) return;
  expect(provider.x).toBeGreaterThan(mic.x + mic.width);
});

test('privacy routes fit without sideways scroll at 390px', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/');
  await page.getByTestId('privacy').scrollIntoViewIfNeeded();
  const overflow = await page.evaluate(
    () => document.documentElement.scrollWidth - document.documentElement.clientWidth,
  );
  expect(overflow).toBeLessThanOrEqual(0);
});
