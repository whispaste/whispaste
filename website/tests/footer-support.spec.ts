import { expect, test } from '@playwright/test';

// Support is one compact zone; the footer keeps every resource link in the
// DOM (collapsed ones too) and has a separate, always-visible legal line.
test('support zone and balanced footer keep all links', async ({ page }) => {
  await page.goto('/en/');
  await expect(page.getByTestId('support-sponsor')).toHaveAttribute('href', /github\.com\/sponsors/);
  await expect(page.getByTestId('support-coffee')).toBeVisible();
  await expect(page.getByTestId('support-roadmap')).toBeVisible();
  await expect(page.getByTestId('support-paypal')).toHaveAttribute('href', /paypal\.com\/donate/);

  const resources = page.getByTestId('footer-resources');
  await expect(resources.locator('a')).toHaveCount(11);
  await expect(page.getByTestId('footer-resources-more')).not.toHaveAttribute('open', '');
  await page.getByTestId('footer-resources-more').locator('summary').click();
  await expect(page.getByTestId('footer-link-linux-stt')).toBeVisible();

  await expect(page.getByTestId('footer-link-impressum')).toBeVisible();
  await expect(page.getByTestId('footer-link-license')).toBeVisible();
  await expect(page.getByTestId('footer-link-sponsor')).toHaveText(/\S/);
});
