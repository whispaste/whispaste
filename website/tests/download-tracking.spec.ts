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

const MODAL_OUTBOUND_TESTIDS = ['modal-star-github', 'modal-star-windows', 'modal-star-macos', 'modal-support'];

// Same intent as preventDownloadNavigation above (module docstring: "neither
// of which should hit the network in a fast, deterministic CI run"), but this
// group's beforeEach never actually installed it — it only closed the popup
// AFTER target="_blank" had already fired a real network request to GitHub/
// the Store review pages. Blocking the browser's default action outright
// (like the sibling test group already does) is good hygiene regardless —
// no real outbound network calls, no stray popups — but it did NOT fully
// explain the "TypeError: received is not iterable" CI failures (2 of the 5
// failing tests, modal-dismiss-close/-later, don't even touch these
// testids). See blockRealMatomoScript below for the actual root cause.
async function preventOutboundNavigation(page: Page, testIds: string[]) {
  await page.addInitScript((ids: string[]) => {
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

// Layout.astro injects the real Matomo bootstrap script unconditionally
// under `import.meta.env.PROD` — true for the `astro preview` build CI runs
// tests against (playwright.config.ts), false for the `astro dev` server
// used locally. That's why this whole file passed every local run but kept
// failing only in CI: once the real matomo.js finishes loading, it replaces
// window._paq (our seeded plain array) with its own Tracker object, and
// whichever test's paqCalls() read happened to lose that race got a
// non-array back — "TypeError: received is not iterable" — regardless of
// which testid the test clicked (matches the 2 dismiss-only failures that
// preventOutboundNavigation, above, could never have fixed). Aborting the
// request keeps window._paq the plain array these tests seed and assert on.
async function blockRealMatomoScript(page: Page) {
  await page.route('https://matomo.silvio-und-maik.de/**', (route) => route.abort());
}

test.describe('download support modal — interaction-scoped Matomo events', () => {
  test.beforeEach(async ({ page }) => {
    await blockRealMatomoScript(page);
    await seedPaq(page);
    await preventOutboundNavigation(page, MODAL_OUTBOUND_TESTIDS);

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
