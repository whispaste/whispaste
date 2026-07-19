import { expect, test } from '@playwright/test';

/**
 * hero-platform-badges.spec.ts — Task #10.
 *
 * The Hero's macOS/Windows/Ubuntu Linux platform badges used to be inert
 * `<span>` pills. They are now links to the matching anchor on `/download/`
 * — this spec verifies each badge's `href` and that clicking it lands on
 * the correct platform card, for both the DE (`/`) and EN (`/en/`) homepage.
 */

const BADGES = ['macos', 'windows', 'linux'] as const;

test.describe('Hero platform badges link to /download/', () => {
  for (const os of BADGES) {
    test(`DE: ${os} badge links to /download/#${os}`, async ({ page }) => {
      await page.goto('/');
      const badge = page.getByTestId(`hero-platform-badge-${os}`);
      await expect(badge).toHaveAttribute('href', `/download/#${os}`);

      await badge.click();
      await expect(page).toHaveURL(`/download/#${os}`);
      await expect(page.locator(`#${os}[data-platform-card="${os}"]`)).toBeVisible();
    });

    test(`EN: ${os} badge links to /en/download/#${os}`, async ({ page }) => {
      await page.goto('/en/');
      const badge = page.getByTestId(`hero-platform-badge-${os}`);
      await expect(badge).toHaveAttribute('href', `/en/download/#${os}`);

      await badge.click();
      await expect(page).toHaveURL(`/en/download/#${os}`);
      await expect(page.locator(`#${os}[data-platform-card="${os}"]`)).toBeVisible();
    });
  }
});
