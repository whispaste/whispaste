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
 * 2. The "Warum zwei Wege" / "Why two ways" section on /download/ used to sit
 *    at the very bottom of the page, after all CTAs. It now renders BEFORE
 *    the two-/four-card platform decision, so visitors understand the
 *    Store-vs-free choice before making it.
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

async function assertDocumentOrder(page: Page, beforeTestId: string, afterTestId: string) {
  const beforePrecedesAfter = await page.evaluate(
    ([beforeId, afterId]) => {
      const before = document.querySelector(`[data-testid="${beforeId}"]`);
      const after = document.querySelector(`[data-testid="${afterId}"]`);
      if (!before || !after) return false;
      // DOCUMENT_POSITION_FOLLOWING (4) is set on `after` relative to `before`
      // when `before` comes first in document order.
      return (before.compareDocumentPosition(after) & Node.DOCUMENT_POSITION_FOLLOWING) !== 0;
    },
    [beforeTestId, afterTestId] as const,
  );
  expect(beforePrecedesAfter).toBe(true);
}

const OS_VARIANTS = ['windows', 'macos', 'linux', undefined] as const;

test.describe('Hero store-hint platform gating', () => {
  for (const os of OS_VARIANTS) {
    test(`hero store-hint visibility for data-os=${os ?? 'unbekannt'} (DE)`, async ({ page }) => {
      await page.goto('/');
      await setOs(page, os);
      const hint = page.getByTestId('hero-store-hint');
      if (os === 'windows' || os === 'macos') {
        // Both have a paid store listing (Microsoft Store / Mac App Store)
        // the hint refers to.
        await expect(hint).toBeVisible();
      } else {
        // Linux (no store listing) AND "unbekannt" (no data-os =
        // crawlers/bots/privacy tools): hidden — it never renders in the
        // ungated all-three-buttons fallback.
        await expect(hint).toBeHidden();
      }
    });
  }

  test('hero store-hint visibility mirrors on the EN page', async ({ page }) => {
    await page.goto('/en/');
    await setOs(page, 'macos');
    await expect(page.getByTestId('hero-store-hint')).toBeVisible();
    await setOs(page, 'windows');
    await expect(page.getByTestId('hero-store-hint')).toBeVisible();
  });

  test('hero store-hint gating holds at 390px mobile width', async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await page.goto('/');
    await setOs(page, 'linux');
    await expect(page.getByTestId('hero-store-hint')).toBeHidden();
    await setOs(page, 'windows');
    await expect(page.getByTestId('hero-store-hint')).toBeVisible();
  });

  test('hero store-hint gating holds in light theme', async ({ page }) => {
    await page.goto('/');
    await page.evaluate(() => document.documentElement.classList.add('light'));
    await setOs(page, 'linux');
    await expect(page.getByTestId('hero-store-hint')).toBeHidden();
    await setOs(page, 'macos');
    await expect(page.getByTestId('hero-store-hint')).toBeVisible();
    await setOs(page, 'windows');
    await expect(page.getByTestId('hero-store-hint')).toBeVisible();
  });
});

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

test.describe('"Warum zwei Wege" / "Why two ways" section order', () => {
  test('renders before the platform card decision on /download/ (DE)', async ({ page }) => {
    await page.goto('/download/');
    await expect(page.getByTestId('why-two-ways')).toBeVisible();
    await expect(page.getByTestId('download-primary-group')).toBeVisible();
    await assertDocumentOrder(page, 'why-two-ways', 'download-primary-group');
  });

  test('renders before the platform card decision on /en/download/ (parity)', async ({ page }) => {
    await page.goto('/en/download/');
    await expect(page.getByTestId('why-two-ways')).toBeVisible();
    await expect(page.getByTestId('download-primary-group')).toBeVisible();
    await assertDocumentOrder(page, 'why-two-ways', 'download-primary-group');
  });

  test('section order holds at 390px mobile width', async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await page.goto('/download/');
    await assertDocumentOrder(page, 'why-two-ways', 'download-primary-group');
  });

  test('section order holds in light theme', async ({ page }) => {
    await page.goto('/download/');
    await page.evaluate(() => document.documentElement.classList.add('light'));
    await assertDocumentOrder(page, 'why-two-ways', 'download-primary-group');
  });
});
