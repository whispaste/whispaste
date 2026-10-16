import { expect, test } from '@playwright/test';

// Below 768px the sticky bar stays inert until the hero is scrolled past, and
// the nav anchors all resolve to sections on the page.
test.use({ viewport: { width: 390, height: 844 } });

test('mobile cta appears after the hero and is inert before', async ({ page }) => {
  await page.goto('/en/');
  const bar = page.getByTestId('mobile-cta');
  await expect(bar).toHaveAttribute('inert', '');
  await expect(page.getByTestId('mobile-cta-download')).toHaveText('Downloads for your computer');

  await page.locator('#features').scrollIntoViewIfNeeded();
  await expect(bar).not.toHaveAttribute('inert', '');
  await expect(bar).toHaveClass(/visible/);
});

test('nav menu anchors point to existing sections', async ({ page }) => {
  await page.goto('/en/');
  for (const id of ['howitworks', 'features', 'privacy', 'faq']) {
    const href = await page.getByTestId(`nav-menu-link-${id}`).getAttribute('href');
    const target = href!.split('#')[1];
    await expect(page.locator(`#${target}`)).toHaveCount(1);
  }
});
