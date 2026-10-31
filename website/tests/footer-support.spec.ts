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

// Footer layout: one rounded panel holds the link columns (each on a
// hairline) and the legal line; no oversized wordmark (rejected by the
// maintainer). Same on the homepage and on subpages, at 390px too.
for (const path of ['/', '/datenschutz/']) {
  test(`footer panel with column rails on ${path}`, async ({ page }) => {
    await page.goto(path);
    const panel = page.getByTestId('footer-panel');
    await expect(panel.locator('.footer-col')).toHaveCount(3);
    for (const width of await panel.locator('.footer-col').evaluateAll((cols) => cols.map((c) => getComputedStyle(c).borderInlineStartWidth))) {
      expect(width).toBe('1px');
    }
    await expect(panel.getByTestId('footer-legal')).toBeVisible();
    expect(await panel.evaluate((el) => parseFloat(getComputedStyle(el).borderTopLeftRadius))).toBeGreaterThan(0);
    await expect(page.getByTestId('footer').locator('svg text')).toHaveCount(0);

    await page.setViewportSize({ width: 390, height: 844 });
    await page.getByTestId('footer-legal').scrollIntoViewIfNeeded();
    const overflow = await page.evaluate(
      () => document.documentElement.scrollWidth - document.documentElement.clientWidth,
    );
    expect(overflow).toBeLessThanOrEqual(0);
  });
}
