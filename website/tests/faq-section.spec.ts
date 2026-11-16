import { expect, test } from '@playwright/test';

// FAQ: three topic groups holding every question, shown as tabs in one panel;
// a #faq-<key> deep link selects the tab and opens that question. The number of
// questions is content and may change, so only "none outside a group" is checked.
test('faq groups keep all questions and deep links open them', async ({ page }) => {
  await page.goto('/en/');
  await expect(page.locator('#faq [data-testid^="faq-group-"]')).toHaveCount(3);
  const total = await page.locator('#faq details').count();
  expect(total).toBeGreaterThan(0);
  await expect(page.locator('#faq [data-testid^="faq-group-"] details')).toHaveCount(total);

  await page.goto('/en/#faq-engines');
  await expect(page.getByTestId('faq-engines')).toHaveAttribute('open', '');
  await expect(page.getByTestId('faq-engines')).toBeVisible();
  await expect(page.getByTestId('faq-tab-local')).toHaveAttribute('aria-selected', 'true');
  await expect(page.getByTestId('faq-free')).not.toHaveAttribute('open', '');
});

test('tabs show one group at a time and work with the keyboard', async ({ page }) => {
  await page.goto('/');
  const tabs = page.getByTestId('faq-tabs');
  await expect(tabs).toBeVisible();
  await expect(tabs.getByRole('tab')).toHaveCount(3);
  await expect(page.getByTestId('faq-group-start')).toBeVisible();
  await expect(page.getByTestId('faq-group-local')).toBeHidden();

  await page.getByTestId('faq-tab-features').click();
  await expect(page.getByTestId('faq-group-features')).toBeVisible();
  await expect(page.getByTestId('faq-group-start')).toBeHidden();
  await expect(page.getByTestId('faq-group-features')).toHaveAttribute('role', 'tabpanel');

  await page.keyboard.press('ArrowLeft');
  await expect(page.getByTestId('faq-tab-local')).toBeFocused();
  await expect(page.getByTestId('faq-group-local')).toBeVisible();
  await page.keyboard.press('End');
  await expect(page.getByTestId('faq-tab-features')).toHaveAttribute('aria-selected', 'true');
});

test('without JavaScript every group is visible and the tabs stay hidden', async ({ browser }) => {
  const context = await browser.newContext({ javaScriptEnabled: false });
  const page = await context.newPage();
  await page.goto('/');
  await expect(page.getByTestId('faq-tabs')).toBeHidden();
  for (const key of ['start', 'local', 'features']) {
    await expect(page.getByTestId(`faq-group-${key}`)).toBeVisible();
  }
  await context.close();
});
