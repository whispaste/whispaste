import { expect, test } from '@playwright/test';

// One large screenshot without device frame; the view buttons swap between
// history and detail editor, and "open full view" opens the lightbox on the
// currently shown view.
test('screenshot views switch and open the lightbox', async ({ page }) => {
  await page.goto('/en/');
  const history = page.getByTestId('screenshots-view-history');
  const detail = page.getByTestId('screenshots-view-detail');
  await history.scrollIntoViewIfNeeded();

  await expect(history).toHaveAttribute('aria-pressed', 'true');
  await expect(page.locator('#app-screenshots .teaser-img:visible')).toHaveCount(1);
  await expect(page.locator('#app-screenshots .teaser-img:visible')).toHaveAttribute('src', /01_workspace_overview/);

  await detail.click();
  await expect(detail).toHaveAttribute('aria-pressed', 'true');
  await expect(history).toHaveAttribute('aria-pressed', 'false');
  await expect(page.locator('#app-screenshots .teaser-img:visible')).toHaveAttribute('src', /02_workspace_detail/);

  await page.getByTestId('screenshots-open').click();
  const dialog = page.locator('dialog[open], [role="dialog"]:visible').first();
  await expect(dialog).toBeVisible();
  await expect(dialog.locator('img').first()).toHaveAttribute('src', /02_workspace_detail/);
});

test('screenshot panel has no device frame and no sideways scroll at 390px', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/');
  const panel = page.locator('#app-screenshots .shots-panel');
  await panel.scrollIntoViewIfNeeded();
  await expect(panel).toBeVisible();
  await expect(page.locator('#app-screenshots .teaser-img:visible')).toHaveCount(1);
  await expect(page.locator('#app-screenshots .mbp')).toHaveCount(0);
  const overflow = await page.evaluate(
    () => document.documentElement.scrollWidth - document.documentElement.clientWidth,
  );
  expect(overflow).toBeLessThanOrEqual(0);
});

for (const path of ['/', '/fr/', '/zh/'] as const) {
  test(`${path}: platform and language facts are listed and the dictation link resolves`, async ({ page }) => {
    await page.goto(path);
    await expect(page.getByTestId('screenshots-facts-os').locator('dd')).toHaveText(['macOS', 'Windows', 'Linux']);
    // The app's own interface languages (L10n.supportedLocales), each marked
    // with its language so screen readers pronounce it correctly.
    const ui = page.getByTestId('screenshots-facts-ui').locator('dd');
    await expect(ui).toHaveCount(6);
    expect(await ui.evaluateAll((els) => els.map((e) => e.getAttribute('lang')))).toEqual(['de', 'en', 'es', 'he', 'pt', 'ru']);
    const link = page.getByTestId('screenshots-facts-dictation').locator('a');
    await expect(link).toHaveAttribute('href', '#languages');
    await expect(link).toContainText('99');
    await expect(page.locator('#languages')).toHaveCount(1);
  });
}
