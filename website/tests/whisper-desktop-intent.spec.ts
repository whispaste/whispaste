import { expect, test, type Page } from '@playwright/test';

/**
 * whisper-desktop-intent.spec.ts — GR-037 to GR-042 on the Whisper-desktop
 * explainer, plus the question path of the contact widget (GR-041).
 *
 * navigator.userAgentData is removed so the classic UA regex (the same one the
 * inline detector in Layout.astro uses) decides, independent of the runner.
 */

const GITHUB_REPO_URL = 'https://github.com/whispaste/whispaste';
const MAC_UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15';
const WIN_UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';
const BOT_UA = 'Mozilla/5.0 (compatible; Bingbot/2.0; +http://www.bing.com/bingbot.htm)';
const IPHONE_UA = 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';

const PAGES = [
  '/whisper-desktop/',
  '/en/whisper-desktop/',
  '/es/whisper-desktop/',
  '/pt/whisper-desktop/',
  '/it/whisper-desktop/',
  '/ru/whisper-desktop/',
  '/zh/whisper-desktop/',
  '/fr/whisper-desktop/',
];

async function hideClientHints(page: Page) {
  await page.addInitScript(() => {
    Object.defineProperty(Navigator.prototype, 'userAgentData', { get: () => undefined });
  });
}

test.describe('title and description (GR-037)', () => {
  for (const path of PAGES) {
    test(`${path} starts title and meta description with WhisPaste`, async ({ page }) => {
      await page.goto(path);
      await expect(page).toHaveTitle(/^WhisPaste/);
      expect((await page.title()).length).toBeLessThanOrEqual(60);
      await expect(page.locator('meta[name="description"]')).toHaveAttribute('content', /^WhisPaste/);
    });
  }
});

test.describe('own-app line under the H1 (GR-038)', () => {
  test('the note follows the H1 and names WhisPaste', async ({ page }) => {
    await page.goto('/en/whisper-desktop/');
    const note = page.getByTestId('page-hero-note');
    await expect(note).toBeVisible();
    await expect(note).toContainText('WhisPaste');
    const followsH1 = await page.evaluate(() => {
      const h1 = document.querySelector('h1');
      const note = document.querySelector('[data-testid="page-hero-note"]');
      return !!h1 && !!note && (h1.compareDocumentPosition(note) & Node.DOCUMENT_POSITION_FOLLOWING) !== 0;
    });
    expect(followsH1).toBe(true);
  });
});

test.describe('download-first hero (GR-039, GR-040)', () => {
  test.describe('visitor without a detectable desktop OS', () => {
    test.use({ userAgent: BOT_UA, viewport: { width: 1440, height: 900 } });

    test('neutral download label, download target and GitHub source link', async ({ page }) => {
      await hideClientHints(page);
      await page.goto('/en/whisper-desktop/');
      const cta = page.getByTestId('whisper-desktop-hero-download');
      await expect(cta).toBeVisible();
      await expect(cta.locator('.wd-dl-label:visible')).toHaveText('Download WhisPaste');
      await expect(cta).toHaveAttribute('href', '/en/download/');

      const source = page.getByTestId('whisper-desktop-source-link');
      await expect(source).toBeVisible();
      await expect(source).toHaveAttribute('href', GITHUB_REPO_URL);
      await expect(source).toHaveAttribute('target', '_blank');
    });
  });

  test.describe('Windows visitor', () => {
    test.use({ userAgent: WIN_UA, viewport: { width: 1440, height: 900 } });

    test('the hero label names Windows', async ({ page }) => {
      await hideClientHints(page);
      await page.goto('/whisper-desktop/');
      await expect(page.locator('html')).toHaveAttribute('data-os', 'windows');
      await expect(page.getByTestId('whisper-desktop-hero-download').locator('.wd-dl-label:visible')).toHaveText('WhisPaste für Windows herunterladen');
    });
  });

  test.describe('macOS visitor', () => {
    test.use({ userAgent: MAC_UA, viewport: { width: 1440, height: 900 } });

    test('the hero label names macOS and a click records one cookieless Matomo event', async ({ page }) => {
      await hideClientHints(page);
      // Matomo runs only in production builds; the queue stands in for it here.
      await page.addInitScript(() => {
        (window as unknown as { _paq: unknown[][] })._paq = [];
        document.addEventListener(
          'click',
          (e) => {
            if ((e.target as HTMLElement).closest('[data-testid="whisper-desktop-hero-download"]')) e.preventDefault();
          },
          true,
        );
      });
      await page.goto('/whisper-desktop/');
      const cta = page.getByTestId('whisper-desktop-hero-download');
      await expect(cta.locator('.wd-dl-label:visible')).toHaveText('WhisPaste für macOS herunterladen');

      await cta.click();
      const queue = await page.evaluate(() => (window as unknown as { _paq: unknown[][] })._paq);
      // Core Web Vitals events share the queue on fast hosts; only the CTA's own category counts here.
      expect(queue.filter((entry) => entry[0] === 'trackEvent' && entry[1] === 'Engagement')).toEqual([
        ['trackEvent', 'Engagement', 'Erklärseite Download-CTA', 'macos'],
      ]);
      expect(await page.context().cookies()).toEqual([]);
    });
  });
});

test.describe('AI image label (EU AI Act Art. 50)', () => {
  for (const path of PAGES) {
    test(`${path} labels the AI-generated device photo`, async ({ page }) => {
      await page.goto(path);
      const badge = page.getByTestId('device-photo-ai-badge');
      await badge.scrollIntoViewIfNeeded();
      await expect(badge).toBeVisible();
      await expect(badge).not.toBeEmpty();
    });
  }
});

test.describe('phone width (GR-040)', () => {
  test.use({ userAgent: IPHONE_UA, viewport: { width: 390, height: 844 } });

  test('no horizontal scroll and the download CTA stays inside the viewport', async ({ page }) => {
    await page.goto('/whisper-desktop/');
    const cta = page.getByTestId('whisper-desktop-hero-download');
    await expect(cta).toBeVisible();
    const box = await cta.boundingBox();
    expect(box).not.toBeNull();
    expect(box!.x + box!.width).toBeLessThanOrEqual(390);
    const overflows = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth);
    expect(overflows).toBe(false);
  });
});

test.describe('contact widget question path (GR-041)', () => {
  test.use({ viewport: { width: 1440, height: 900 } });

  test('the question path links to the download page, the problem path does not', async ({ page }) => {
    await page.goto('/en/whisper-desktop/');
    await page.getByTestId('contact-launcher').click();
    await expect(page.getByTestId('contact-panel')).toBeVisible();
    await page.getByTestId('contact-kind-question').click();
    await expect(page.getByTestId('contact-form')).toBeVisible();
    await expect(page.getByTestId('contact-download-link')).toBeVisible();
    await expect(page.getByTestId('contact-download-link')).toHaveAttribute('href', '/en/download/');
  });

  test('the download link is not shown on the problem path', async ({ page }) => {
    await page.goto('/en/whisper-desktop/');
    await page.getByTestId('contact-launcher').click();
    await page.getByTestId('contact-kind-problem').click();
    await expect(page.getByTestId('contact-form')).toBeVisible();
    await expect(page.getByTestId('contact-download-link')).toBeHidden();
  });
});
