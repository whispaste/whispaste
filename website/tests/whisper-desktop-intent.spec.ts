import { expect, test, type Page } from '@playwright/test';

/**
 * whisper-desktop-intent.spec.ts — GR-037 to GR-042 on the Whisper-desktop
 * explainer, plus the question path of the contact widget (GR-041).
 *
 * navigator.userAgentData is removed so the classic UA regex (the same one the
 * inline detector in Layout.astro uses) decides, independent of the runner.
 */

const MAC_UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15';
const WIN_UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';
const BOT_UA = 'Mozilla/5.0 (compatible; Bingbot/2.0; +http://www.bing.com/bingbot.htm)';
const LINUX_UA = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

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
  test('the note names WhisPaste', async ({ page }) => {
    await page.goto('/en/whisper-desktop/');
    const note = page.getByTestId('page-hero-note');
    await expect(note).toBeVisible();
    await expect(note).toContainText('WhisPaste');
  });
});

// #1949 (D-005): the hero's main action is the visitor's store button with
// the purchase line under it; nothing next to it points to GitHub or the
// free variant, every other route is one quiet link to the download page.
test.describe('store-first hero (GR-039, GR-040, #1949)', () => {
  test.describe('visitor without a detectable desktop OS', () => {
    test.use({ userAgent: BOT_UA, viewport: { width: 1440, height: 900 } });

    test('both store buttons, the purchase line and the download link, no GitHub', async ({ page }) => {
      await hideClientHints(page);
      await page.goto('/en/whisper-desktop/');
      const buy = page.getByTestId('whisper-desktop-hero-buy');
      await expect(buy).toHaveAttribute('data-download-placement', 'hero-whisper-desktop');
      await expect(buy.getByTestId('store-button')).toBeVisible();
      await expect(buy.getByTestId('mac-store-button')).toBeVisible();
      await expect(buy.getByTestId('whisper-desktop-hero-store-note')).toContainText(/one-time purchase, no subscription/i);
      const cta = page.getByTestId('whisper-desktop-hero-download');
      await expect(cta).toBeVisible();
      await expect(cta).toHaveAttribute('href', '/en/download/');
      // innerText skips the buttons that the OS gate hides.
      expect(await page.getByTestId('lp-hero').innerText()).not.toMatch(/github|free/i);
      await expect(page.getByTestId('lp-hero').locator('a[href*="github.com"]:visible')).toHaveCount(0);
    });
  });

  test.describe('Linux visitor', () => {
    test.use({ userAgent: LINUX_UA, viewport: { width: 1440, height: 900 } });

    test('sees the Linux download instead of a store button', async ({ page }) => {
      await hideClientHints(page);
      await page.goto('/en/whisper-desktop/');
      const buy = page.getByTestId('whisper-desktop-hero-buy');
      await expect(buy.getByTestId('linux-button')).toBeVisible();
      await expect(buy.getByTestId('store-button')).toBeHidden();
      await expect(buy.getByTestId('mac-store-button')).toBeHidden();
    });
  });

  test.describe('Windows visitor', () => {
    test.use({ userAgent: WIN_UA, viewport: { width: 1440, height: 900 } });

    test('the visitor OS is detected as Windows', async ({ page }) => {
      await hideClientHints(page);
      await page.goto('/whisper-desktop/');
      await expect(page.locator('html')).toHaveAttribute('data-os', 'windows');
    });
  });

  test.describe('macOS visitor', () => {
    test.use({ userAgent: MAC_UA, viewport: { width: 1440, height: 900 } });

    test('a click on the hero download records one cookieless Matomo event', async ({ page }) => {
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

// #1937: the page serves dictation and file transcription and shows both ways
// to get the app; since #1949 the store card leads with the large buttons and
// the free route follows as a text link. The purchase answer is in the FAQ
// schema.
test.describe('dictation, files and both ways to get the app (#1937)', () => {
  test.use({ userAgent: WIN_UA });

  test('shows both uses and both ways to get the app', async ({ page }) => {
    await hideClientHints(page);
    await page.goto('/en/whisper-desktop/');
    await expect(page.getByTestId('whisper-desktop-use-dictate')).toBeVisible();
    await expect(page.getByTestId('whisper-desktop-use-files')).toContainText('MP4');
    const free = page.getByTestId('whisper-desktop-get-free-link');
    await expect(free).toHaveAttribute('href', /\/en\/download\/(#windows)?$/);
    const store = page.getByTestId('whisper-desktop-get-store');
    await expect(store).toContainText('One-time purchase, no subscription');
    await expect(store.getByTestId('store-button')).toBeVisible();
    await expect(store.getByTestId('store-button')).toContainText('Buy');
    await expect(store).toHaveAttribute('data-download-placement', 'get-whisper-desktop');
    await expect(store).not.toContainText(/github/i);
    // The store card comes before the free route.
    const order = await page.evaluate(() => {
      const a = document.querySelector('[data-testid="whisper-desktop-get-store"]');
      const b = document.querySelector('[data-testid="whisper-desktop-get-free"]');
      return a && b ? a.compareDocumentPosition(b) & Node.DOCUMENT_POSITION_FOLLOWING : 0;
    });
    expect(order).toBeTruthy();
  });

  test('FAQ and HowTo schema cover files and the purchase question', async ({ page }) => {
    await page.goto('/whisper-desktop/');
    const blocks = await page.locator('script[type="application/ld+json"]').allTextContents();
    const faq = blocks.map((b) => JSON.parse(b)).find((j) => j['@type'] === 'FAQPage');
    const names = faq.mainEntity.map((q: { name: string }) => q.name);
    expect(names).toContain('Warum im Store kaufen, wenn es auf GitHub kostenlos ist?');
    expect(names).toContain('Kann WhisPaste Audio- und Videodateien mit Whisper transkribieren?');
    const howTo = blocks.map((b) => JSON.parse(b)).find((j) => j['@type'] === 'HowTo');
    expect(howTo.step).toHaveLength(4);
  });
});

// Maintainer 2026-11-19: store buttons carry no version notes; the Mac buy
// button stands on its own, the free route stays a quiet text link (#1949).
test.describe('Mac buy button without version notes', () => {
  test.use({ userAgent: MAC_UA });
  test('store card shows the Mac button and no "next store update" note', async ({ page }) => {
    await hideClientHints(page);
    await page.goto('/en/whisper-desktop/');
    const store = page.getByTestId('whisper-desktop-get-store');
    await expect(store.getByTestId('mac-store-button')).toBeVisible();
    await expect(page.locator('main')).not.toContainText(/next store update/i);
    await expect(page.getByTestId('whisper-desktop-get-free-link')).not.toHaveClass(/wp-cta/);
  });
});

// #1949: the differences block keeps the original page order: hero, benefit
// strip, uses, how-to, then the block right before the purchase section. The
// baseline is one line, two cards carry the differences, each with proof; the
// block has no buy button of its own (maintainer 2026-11-19).
test.describe('differences block (#1949)', () => {
  for (const path of PAGES) {
    test(`${path} has the block before the purchase section, with proof per card`, async ({ page }) => {
      await page.goto(path);
      const block = page.getByTestId('differences');
      const next = await page.getByTestId('whisper-desktop-differences').evaluate((el) => el.nextElementSibling?.getAttribute('data-testid'));
      expect(next).toBe('whisper-desktop-get');
      await expect(page.locator('.benefit-strip')).toHaveCount(1);
      await expect(block.getByTestId('store-button')).toHaveCount(0);
      await expect(block.getByTestId('mac-store-button')).toHaveCount(0);
      await expect(block.getByTestId('differences-baseline')).not.toBeEmpty();
      for (const key of ['smartmode', 'localAi']) {
        await expect(block.getByTestId(`differences-${key}`)).toBeVisible();
      }
      for (const key of ['smartmode', 'localAi']) {
        await expect(block.getByTestId(`differences-${key}-proof`)).toHaveAttribute('href', /\/screenshots\/$|#faq-/);
      }
      await expect(block.getByTestId('differences-smartmode-shot').locator('img')).toHaveAttribute('src', /06_smart_mode\.webp$/);
      await expect(block.locator('a[href*="github.com"]:visible')).toHaveCount(0);
    });
  }
});
