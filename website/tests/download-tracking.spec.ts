import { expect, test } from '@playwright/test';
import type { Page } from '@playwright/test';

/**
 * download-tracking.spec.ts — Slice 11 (Block C, Website).
 *
 * Verifies that ALL download paths on /download/ (Microsoft Store, Mac App
 * Store, Windows .exe, macOS DMG, Linux) dispatch the `download:triggered`
 * CustomEvent — previously only the Store buttons did, so Free-Downloader
 * engagement fell through the tracking grid.
 *
 * These specs intercept navigation instead of letting real downloads fire:
 * the download links point at real GitHub release assets, which should not
 * hit the network in a fast, deterministic CI run.
 */

const DOWNLOAD_TESTIDS = [
  'store-button',
  'mac-store-button',
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

// Layout.astro injects the real Matomo bootstrap script under
// `import.meta.env.PROD` — true for the `astro preview` build CI runs tests
// against, false for the local `astro dev` server. Once the real matomo.js
// loads it replaces window._paq and perturbs timing mid-test; aborting the
// request keeps runs deterministic.
async function blockRealMatomoScript(page: Page) {
  await page.route('https://matomo.silvio-und-maik.de/**', (route) => route.abort());
}

test.describe('download page — download:triggered dispatch', () => {
  test.beforeEach(async ({ page }) => {
    // Same real-network hazard as blockRealMatomoScript above (see its
    // comment): `astro preview`/PROD — what CI and the pre-push hook test
    // against, unlike the local `astro dev` server — loads the real
    // matomo.js unconditionally. Layout.astro's own `download:triggered`
    // listener (Layout.astro:190) pushes to `window._paq`, and matomo.js
    // loading mid-test can perturb timing/global state regardless of
    // which button was clicked — this group just never blocked it, so it
    // kept intermittently losing that race (root-caused 2026-07-28 via a
    // recurring, non-random "linux-deb-button" failure that never
    // reproduced against the dev server, only against the hook's
    // build+preview run).
    await blockRealMatomoScript(page);
    await preventDownloadNavigation(page, DOWNLOAD_TESTIDS);
    await page.goto('/download/');
  });

  for (const testId of DOWNLOAD_TESTIDS) {
    test(`"${testId}" dispatches download:triggered`, async ({ page }) => {
      // Other systems' cards sit behind "Andere Plattformen" once the visitor's
      // OS is known (ticket 19); open it the way a visitor would.
      const otherToggle = page.getByTestId('other-platforms-toggle');
      if ((await otherToggle.isVisible()) && (await otherToggle.getAttribute('aria-expanded')) !== 'true') {
        await otherToggle.click();
      }
      await page.getByTestId(testId).first().click();
      // A bare one-shot `page.evaluate()` right after `.click()` is a known
      // flake source: click() resolving doesn't strictly guarantee the
      // element's synchronous onclick (and its CustomEvent dispatch) has
      // already run by the time the next CDP round-trip reads window state
      // — under scheduling pressure the JS can lag the click by a tick.
      // expect.poll() retries the read instead of trusting a single sample,
      // without weakening what's actually asserted (still exactly 1).
      await expect
        .poll(() =>
          page.evaluate(
            () => (window as unknown as { __downloadTriggeredCount: number }).__downloadTriggeredCount,
          ),
        )
        .toBe(1);
    });
  }
});
