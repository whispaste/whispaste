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
