import { expect, test } from '@playwright/test';

// FAQ: three topic groups holding all twelve questions; a #faq-<key> deep link
// opens that question.
test('faq groups keep all questions and deep links open them', async ({ page }) => {
  await page.goto('/en/');
  await expect(page.locator('#faq [data-testid^="faq-group-"]')).toHaveCount(3);
  await expect(page.locator('#faq details')).toHaveCount(12);

  await page.goto('/en/#faq-engines');
  await expect(page.getByTestId('faq-engines')).toHaveAttribute('open', '');
  await expect(page.getByTestId('faq-free')).not.toHaveAttribute('open', '');
});
