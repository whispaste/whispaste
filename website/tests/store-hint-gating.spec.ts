import { expect, test } from '@playwright/test';
import type { Page } from '@playwright/test';

/**
 * store-hint-gating.spec.ts — Slice 13 (Block C, Website, issue 13).
 *
 * Two independent fixes on this slice:
 *
 * 1. The "Unterstützt das Projekt" / "Support the project" Store-hint under
 *    the Hero and Pricing CTAs used to render regardless of platform, so
 *    macOS/Linux visitors saw a Microsoft-Store-related hint under their free
 *    DMG/AppImage download (there was no Store path on those platforms). It is
 *    gated with `data-requires-os="windows macos"` (global.css, `~=` token
 *    match), which rides the same `data-os` detection as the platform-adaptive
 *    download buttons but is STRICTER: the hint shows only when Windows or
 *    macOS is positively detected — both now have a paid store listing
 *    (Microsoft Store / Mac App Store) the hint refers to. Linux has neither,
 *    so it stays hidden there. In the unknown-OS fallback (no data-os: all
 *    three CTAs visible) it also stays hidden, because a Store-only hint under
 *    three equal-rank buttons would read as applying to all of them.
 *
 * `data-os` is driven directly via page.evaluate (not addInitScript) —
 * mirrors the established pattern in tests/landing.spec.ts
 * (assertNavDownloadAdaptsToOs): the CSS attribute selectors react instantly,
 * no reload needed.
 */

async function setOs(page: Page, os: 'windows' | 'macos' | 'linux' | undefined) {
  await page.evaluate((value) => {
    if (value) {
      document.documentElement.dataset.os = value;
    } else {
      delete document.documentElement.dataset.os;
    }
  }, os);
}

const OS_VARIANTS = ['windows', 'macos', 'linux', undefined] as const;

test.describe('Pricing store-hint platform gating', () => {
  for (const os of OS_VARIANTS) {
    test(`pricing store-hint visibility for data-os=${os ?? 'unbekannt'} (DE)`, async ({ page }) => {
      await page.goto('/');
      await setOs(page, os);
      const hint = page.getByTestId('pricing-store-hint');
      if (os === 'windows' || os === 'macos') {
        await expect(hint).toBeVisible();
      } else {
        // Same strict gate as the hero hint: hidden for Linux and the
        // unknown-OS fallback (neither has a store listing).
        await expect(hint).toBeHidden();
      }
    });
  }

  test('pricing store-hint visibility mirrors on the EN page', async ({ page }) => {
    await page.goto('/en/');
    await setOs(page, 'linux');
    await expect(page.getByTestId('pricing-store-hint')).toBeHidden();
    await setOs(page, 'macos');
    await expect(page.getByTestId('pricing-store-hint')).toBeVisible();
    await setOs(page, 'windows');
    await expect(page.getByTestId('pricing-store-hint')).toBeVisible();
  });
});

// The store perks (support, reviewed, auto-updates) sit inside the "two ways"
// card so the reasons to pick the store build are next to the decision.
test('download page lists the three store perks inside "why two ways"', async ({ page }) => {
  await page.goto('/en/download/');
  const card = page.getByTestId('why-two-ways');
  for (const key of ['support', 'safe', 'updates']) {
    await expect(card.getByTestId(`download-store-perks-${key}`)).toBeVisible();
  }
});
