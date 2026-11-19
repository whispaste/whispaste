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
// event free to bubble to Layout.astro's delegated click listener — which
// dispatches `download:triggered` for [data-download-trigger]. Also counts CustomEvent dispatches
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
      // delegated click listener (and its CustomEvent dispatch) has
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

/**
 * #1938: one Matomo event "Download / <channel> / <placement>" per store or
 * release link, and the placement as store campaign parameter. A stub
 * `_paq` records what would be sent; Matomo itself never loads on
 * 127.0.0.1 (hostname guard in Layout.astro) and is blocked anyway.
 */
async function recordPaq(page: Page) {
  await page.addInitScript(() => {
    const calls: unknown[][] = [];
    (window as unknown as { __paqCalls: unknown[][] }).__paqCalls = calls;
    (window as unknown as { _paq: { push: (args: unknown[]) => void } })._paq = {
      push: (args) => {
        calls.push(args);
      },
    };
  });
}

function downloadEvents(page: Page) {
  return page.evaluate(() =>
    (window as unknown as { __paqCalls: unknown[][] }).__paqCalls.filter(
      (call) => call[0] === 'trackEvent' && call[1] === 'Download',
    ),
  );
}

test.describe('download event with channel and placement (#1938)', () => {
  test.beforeEach(async ({ page }) => {
    await blockRealMatomoScript(page);
    await recordPaq(page);
    await preventDownloadNavigation(page, ['store-button', 'github-windows-button']);
  });

  test('download page: Microsoft Store and GitHub installer', async ({ page }) => {
    await page.goto('/en/download/');
    const store = page.getByTestId('store-button').first();
    await expect(store).toHaveAttribute('href', 'https://apps.microsoft.com/detail/9p22jvkrq2v0?cid=web-download-page');
    await store.click();
    await page.getByTestId('github-windows-button').click();
    await expect
      .poll(() => downloadEvents(page))
      .toEqual([
        ['trackEvent', 'Download', 'store-ms', 'download-page'],
        ['trackEvent', 'Download', 'github-exe', 'download-page'],
      ]);
  });

  test('home hero: store link carries the hero-home placement', async ({ page }) => {
    await page.goto('/en/');
    const store = page.locator('[data-download-placement="hero-home"]').getByTestId('store-button');
    await expect(store).toHaveAttribute('href', /[?&]cid=web-hero-home$/);
    await store.click();
    await expect.poll(() => downloadEvents(page)).toEqual([['trackEvent', 'Download', 'store-ms', 'hero-home']]);
  });

  // #1949: every new store button surface has its own placement.
  for (const { path, placement } of [
    { path: '/en/whisper-desktop/', placement: 'hero-whisper-desktop' },
    { path: '/en/whisper-desktop/', placement: 'get-whisper-desktop' },
    { path: '/en/whisper-desktop/', placement: 'rail-whisper-desktop' },
    { path: '/en/whisper-desktop/', placement: 'end-whisper-desktop' },
    // Long-tail explainer pages: hero, rail and closing panel each sell.
    { path: '/en/gpu-compatibility/', placement: 'hero-gpu-compatibility' },
    { path: '/gpu-kompatibilitaet/', placement: 'rail-gpu-compatibility' },
    { path: '/fr/gpu-compatibility/', placement: 'end-gpu-compatibility' },
    { path: '/blog/lokal-diktieren-ohne-nvidia-pflicht/', placement: 'rail-blog' },
    { path: '/en/screenshots/', placement: 'hero-screenshots' },
  ]) {
    test(`${path}: store link carries the ${placement} placement`, async ({ page }) => {
      // The rail only shows from 1280px on.
      await page.setViewportSize({ width: 1440, height: 900 });
      await page.goto(path);
      const store = page.locator(`[data-download-placement="${placement}"]`).getByTestId('store-button');
      await expect(store).toHaveAttribute('href', new RegExp(`[?&]cid=web-${placement}$`));
      await store.scrollIntoViewIfNeeded();
      await store.click();
      await expect.poll(() => downloadEvents(page)).toEqual([['trackEvent', 'Download', 'store-ms', placement]]);
    });
  }
});

test.describe('help links and FAQ events', () => {
  test.beforeEach(async ({ page }) => {
    await blockRealMatomoScript(page);
    await recordPaq(page);
  });

  test('download page: the store link in the SmartScreen help has its own placement', async ({ page }) => {
    await page.goto('/en/download/');
    const link = page.getByTestId('download-sac-store-link');
    await expect(link).toHaveAttribute('href', /[?&]cid=web-download-smartscreen-help$/);
  });

  // Live Matomo filed AppImage clicks as outlinks: the build on main predates
  // #1938. On dev the AppImage counts twice over: the Download event below and
  // Matomo's own download report (addDownloadExtensions in the bootstrap).
  test('AppImage: Download event, and the bootstrap registers the extension', async ({ page }) => {
    await preventDownloadNavigation(page, ['linux-appimage-button']);
    await page.goto('/en/download/');
    // Text matching skips <script> content, so read it directly.
    const bootstraps = await page.evaluate(() =>
      [...document.querySelectorAll('script:not([src])')]
        .map((script) => script.textContent ?? '')
        .filter((text) => text.includes('addDownloadExtensions')),
    );
    expect(bootstraps).toHaveLength(1);
    expect(bootstraps[0]).toContain('"addDownloadExtensions", "AppImage"');
    const otherToggle = page.getByTestId('other-platforms-toggle');
    if ((await otherToggle.isVisible()) && (await otherToggle.getAttribute('aria-expanded')) !== 'true') {
      await otherToggle.click();
    }
    await page.getByTestId('linux-appimage-button').first().click();
    await expect.poll(() => downloadEvents(page)).toEqual([['trackEvent', 'Download', 'appimage', 'download-page']]);
  });

  test('opening a purchase question sends FAQ / <key> / <page> once', async ({ page }) => {
    await page.goto('/en/download/');
    const row = page.getByTestId('download-faq-whyPay');
    await row.locator('summary').click();
    await row.locator('summary').click();
    await row.locator('summary').click();
    await expect
      .poll(() =>
        page.evaluate(() =>
          (window as unknown as { __paqCalls: unknown[][] }).__paqCalls.filter(
            (call) => call[0] === 'trackEvent' && call[1] === 'FAQ',
          ),
        ),
      )
      .toEqual([['trackEvent', 'FAQ', 'whyPay', 'download-page']]);
  });
});
