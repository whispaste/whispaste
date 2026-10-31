import { expect, test } from '@playwright/test';

// Testimonials are fetched at build time; without approved quotes the section
// is omitted entirely, so every check first asks whether it rendered.
test('the longest quote leads as a dark panel, the rest as light tiles', async ({ page }) => {
  await page.goto('/en/');
  const section = page.getByTestId('testimonials');
  test.skip((await section.count()) === 0, 'no approved testimonials at build time');

  const cards = section.locator('[data-testid^="testimonials-card-"]');
  const count = await cards.count();
  expect(count).toBeGreaterThan(0);
  const feature = section.locator('.testimonial-card--feature');
  await expect(feature).toHaveCount(1);
  await expect(feature).toHaveAttribute('data-surface', 'dark');

  const lengths = await cards.evaluateAll((els) =>
    els.map((el) => el.querySelector('blockquote')?.textContent?.length ?? 0),
  );
  const featureLength = await feature.locator('blockquote').evaluate((el) => el.textContent?.length ?? 0);
  expect(featureLength).toBe(Math.max(...lengths));
  for (let i = 0; i < count; i++) {
    await expect(cards.nth(i).getByRole('img')).toHaveAttribute('aria-label', /^[0-5]\/5$/);
  }
});

test('testimonials fit without sideways scroll at 390px', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/');
  const section = page.getByTestId('testimonials');
  test.skip((await section.count()) === 0, 'no approved testimonials at build time');
  await section.scrollIntoViewIfNeeded();
  const overflow = await page.evaluate(
    () => document.documentElement.scrollWidth - document.documentElement.clientWidth,
  );
  expect(overflow).toBeLessThanOrEqual(0);
});
