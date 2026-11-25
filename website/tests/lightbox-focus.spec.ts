import { expect, test } from '@playwright/test';

// #1908: opening a screenshot by keyboard must move focus into the dialog,
// keep the background unreachable, and Escape must close it and return focus
// to the trigger -- on the home teaser and on the /screenshots/ gallery, in
// every landing locale.
const LOCALES = ['de', 'en', 'es', 'pt', 'it', 'ru', 'zh', 'fr'] as const;
const prefix = (l: string) => (l === 'de' ? '/' : `/${l}/`);

const cases = LOCALES.flatMap((l) => [
  { path: prefix(l), trigger: '[data-testid="screenshots-open"]' },
  { path: `${prefix(l)}screenshots/`, trigger: '.gallery-thumb-btn' },
]);

const focusInDialog = () => !!document.activeElement?.closest('#screenshot-lightbox');

for (const { path, trigger } of cases) {
  test(`${path}: keyboard-opened lightbox takes focus and Escape restores it`, async ({ page }) => {
    await page.goto(path);
    const btn = page.locator(trigger).first();
    await btn.scrollIntoViewIfNeeded();
    await btn.focus();
    await page.keyboard.press('Enter');

    const dialog = page.locator('#screenshot-lightbox');
    await expect(dialog).toHaveAttribute('data-open', '');
    expect(await page.evaluate(focusInDialog)).toBe(true);

    // Tab cycles inside the dialog, never into the covered page.
    for (let i = 0; i < 4; i++) {
      await page.keyboard.press('Tab');
      expect(await page.evaluate(focusInDialog)).toBe(true);
    }

    await page.keyboard.press('Escape');
    await expect(dialog).not.toHaveAttribute('data-open', '');
    expect(await btn.evaluate((el) => el === document.activeElement)).toBe(true);
  });
}
