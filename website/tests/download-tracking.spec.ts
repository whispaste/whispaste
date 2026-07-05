import { expect, test } from '@playwright/test';
import type { Page } from '@playwright/test';

/**
 * download-tracking.spec.ts — Slice 11 (Block C, Website).
 *
 * Verifies two engagement-tracking gaps closed by this issue:
 *
 * 1. ALL THREE download paths on /download/ (Store/Apple, Windows .exe,
 *    Linux) dispatch the `download:triggered` CustomEvent — previously only
 *    the Store/Apple buttons did, so Free-Downloader engagement fell through
 *    the tracking grid.
 * 2. The DownloadSupportModal's three interactions (star/support/dismiss)
 *    each push their OWN interaction-scoped Matomo `trackEvent` — not tied
 *    to CTA layout/position, so a later CTA-reweighting slice (Slice 12)
 *    won't invalidate the event names.
 *
 * These specs intercept navigation instead of letting real downloads/outbound
 * clicks fire: the download links point at real GitHub release assets and the
 * modal's action links open new tabs (target="_blank"), neither of which
 * should hit the network in a fast, deterministic CI run.
 */

const DOWNLOAD_TESTIDS = [
  'store-button',
  'apple-button',
  'github-windows-button',
  'linux-appimage-button',
  'linux-deb-button',
];

// Registers a capturing click listener that cancels the browser's default
// action (download/navigation) for the given testids, while leaving the
// event free to bubble to the target's own inline `onclick` handler — which
// is what dispatches `download:triggered`. Also counts CustomEvent dispatches
// on `window.__downloadTriggeredCount` for the test to read back.
async function preventDownloadNavigation(page: Page, testIds: string[]) {
  await page.addInitScript((ids: string[]) => {
    (window as unknown as { __downloadTriggeredCount: number }).__downloadTriggeredCount = 0;
    document.addEventListener('download:triggered', () => {
      (window as unknown as { __downloadTriggeredCount: number }).__downloadTriggeredCount += 1;
    });
    document.addEventListener(
      'click',
      (e) => {
        const target = e.target as HTMLElement | null;
        const link = target?.closest('a[data-testid]');
        const testId = link?.getAttribute('data-testid') ?? '';
        if (link && ids.includes(testId)) {
          e.preventDefault();
        }
      },
      true,
    );
  }, testIds);
}

async function seedPaq(page: Page) {
  // Simulates a loaded Matomo tracker (matches the `if (window._paq)` runtime
  // guard used across the codebase — Matomo itself only loads in prod builds).
  await page.addInitScript(() => {
    (window as unknown as { _paq: unknown[][] })._paq = [];
  });
}

test.describe('download page — download:triggered dispatch', () => {
  test.beforeEach(async ({ page }) => {
    await preventDownloadNavigation(page, DOWNLOAD_TESTIDS);
    await page.goto('/download/');
  });

  for (const testId of DOWNLOAD_TESTIDS) {
    test(`"${testId}" dispatches download:triggered`, async ({ page }) => {
      await page.getByTestId(testId).first().click();
      const count = await page.evaluate(
        () => (window as unknown as { __downloadTriggeredCount: number }).__downloadTriggeredCount,
      );
      expect(count).toBe(1);
    });
  }
});

test.describe('download support modal — interaction-scoped Matomo events', () => {
  test.beforeEach(async ({ page, context }) => {
    await seedPaq(page);
    // The modal's star/support links open in a new tab (target="_blank");
    // close any tab that pops up so it can't leak into later assertions.
    context.on('page', (popup) => {
      popup.close().catch(() => {});
    });

    await page.goto('/download/');
    await page.evaluate(() => {
      (document.getElementById('dl-support-modal') as HTMLDialogElement).showModal();
    });
  });

  async function paqCalls(page: Page) {
    return page.evaluate(() => (window as unknown as { _paq: unknown[][] })._paq);
  }

  test('GitHub star click fires a star-scoped event', async ({ page }) => {
    await page.getByTestId('modal-star-github').click();
    const calls = await paqCalls(page);
    expect(calls).toContainEqual(['trackEvent', 'Engagement', 'Support-Modal Sternklick', 'github']);
  });

  test('Microsoft Store rating click fires the SAME star-scoped event name', async ({ page }) => {
    await page.getByTestId('modal-star-windows').click();
    const calls = await paqCalls(page);
    expect(calls).toContainEqual(['trackEvent', 'Engagement', 'Support-Modal Sternklick', 'windows']);
  });

  test('sponsor/support click fires a support-scoped event, distinct from the star event', async ({ page }) => {
    await page.getByTestId('modal-support').click();
    const calls = await paqCalls(page);
    expect(calls).toContainEqual(['trackEvent', 'Engagement', 'Support-Modal Support-Klick']);
    expect(calls.some((c) => c[2] === 'Support-Modal Sternklick')).toBe(false);
  });

  test('close (X) click fires a dismiss-scoped event and closes the modal', async ({ page }) => {
    await page.getByTestId('modal-dismiss-close').click();
    const calls = await paqCalls(page);
    expect(calls).toContainEqual(['trackEvent', 'Engagement', 'Support-Modal Dismiss', 'close']);
    await expect(page.locator('#dl-support-modal')).toBeHidden();
  });

  test('"maybe later" click fires the SAME dismiss-scoped event name and closes the modal', async ({ page }) => {
    await page.getByTestId('modal-dismiss-later').click();
    const calls = await paqCalls(page);
    expect(calls).toContainEqual(['trackEvent', 'Engagement', 'Support-Modal Dismiss', 'later']);
    await expect(page.locator('#dl-support-modal')).toBeHidden();
  });
});
