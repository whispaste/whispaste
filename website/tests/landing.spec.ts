import { expect, test } from '@playwright/test';
import type { Locator, Page } from '@playwright/test';
import { getLivePkgManagersGroupedByPlatform } from '../src/data/platforms.ts';

const PLATFORM_LABEL: Record<string, string> = {
  windows: 'Windows',
  macos: 'macOS',
  linux: 'Linux',
};

test.beforeEach(async ({ page }) => {
  await page.addInitScript(() => {
    window.localStorage.clear();
  });
});

test('hero CTA contains platform download button(s)', async ({ page }) => {
  await page.goto('/');

  // At least one download button must be visible (platform-adaptive: one or both shown)
  const storeBtn = page.getByTestId('store-button').first();
  const appleBtn = page.getByTestId('apple-button').first();
  const storeVisible = await storeBtn.isVisible();
  const appleVisible = await appleBtn.isVisible();
  expect(storeVisible || appleVisible).toBe(true);
});

test('language toggle switches the landing page between DE and EN', async ({ page }) => {
  await page.goto('/');

  const heroHeading = page.locator('section h1').first();
  await expect(heroHeading).toContainText('Drücken. Sprechen.');
  await page.getByTestId('lang-toggle').click();
  await page.waitForURL(/\/en\/?$/);
  await expect(page.locator('section h1').first()).toContainText('Press. Speak.');
});

test('FAQ section is visible and has accordion items', async ({ page }) => {
  await page.goto('/');

  const faq = page.locator('#faq');
  await faq.scrollIntoViewIfNeeded();
  await expect(faq).toBeVisible();
  await expect(faq.locator('details')).toHaveCount(9);
});

test('legal pages load without 404s', async ({ page }) => {
  await page.goto('/datenschutz/');
  await expect(page.locator('#pageTitle')).toBeVisible();

  await page.goto('/impressum/');
  await expect(page.locator('#pageTitle')).toBeVisible();
});

test('download page has Store and GitHub sections', async ({ page }) => {
  await page.goto('/download/');
  await expect(page.locator('main h1').first()).toContainText('WhisPaste herunterladen');
  await expect(page.locator('main h2').first()).toContainText('Microsoft Store');
  // GitHub free download section — Windows button has data-testid="github-windows-button"
  await expect(page.getByTestId('github-windows-button')).toBeVisible();
});

test('package manager copy button copies the command and shows success feedback (DE)', async ({
  page,
  context,
}) => {
  await context.grantPermissions(['clipboard-read', 'clipboard-write']);
  await page.goto('/download/');

  // Package managers section is collapsed by default — open it first.
  await page.getByTestId('pkg-managers').locator('> summary').click();

  const copyBtn = page.getByTestId('pkg-copy-scoop');
  await expect(copyBtn).toBeVisible();
  await copyBtn.click();

  // Clipboard actually received the scoop install commands.
  const clipboardText = await page.evaluate(() => navigator.clipboard.readText());
  expect(clipboardText).toContain('scoop install whispaste');

  // Visual success signal: the button flips into its "copied" state.
  await expect(copyBtn).toHaveClass(/is-copied/);
  await expect(copyBtn.locator('.pkg-copy-btn__label')).toHaveText('Kopiert!');

  // Screen readers get an explicit announcement via a live region.
  const status = page.locator('#pkg-copy-status');
  await expect(status).toHaveText('Kopiert!');

  // Feedback reverts back to the idle label after the timeout.
  await expect(copyBtn.locator('.pkg-copy-btn__label')).toHaveText('Kopieren', { timeout: 4000 });
  await expect(copyBtn).not.toHaveClass(/is-copied/);
});

test('package manager copy button works identically on the EN download page', async ({
  page,
  context,
}) => {
  await context.grantPermissions(['clipboard-read', 'clipboard-write']);
  await page.goto('/en/download/');

  await page.getByTestId('pkg-managers').locator('> summary').click();

  const copyBtn = page.getByTestId('pkg-copy-scoop');
  await copyBtn.click();

  const clipboardText = await page.evaluate(() => navigator.clipboard.readText());
  expect(clipboardText).toContain('scoop install whispaste');
  await expect(copyBtn).toHaveClass(/is-copied/);
  await expect(copyBtn.locator('.pkg-copy-btn__label')).toHaveText('Copied!');
  await expect(page.locator('#pkg-copy-status')).toHaveText('Copied!');
});

test('package manager copy success icon skips its entrance animation under prefers-reduced-motion', async ({
  page,
  context,
}) => {
  await context.grantPermissions(['clipboard-read', 'clipboard-write']);
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await page.goto('/download/');

  await page.getByTestId('pkg-managers').locator('> summary').click();
  const copyBtn = page.getByTestId('pkg-copy-scoop');
  await copyBtn.click();

  await expect(copyBtn).toHaveClass(/is-copied/);
  const animationName = await copyBtn
    .locator('.pkg-copy-btn__icon--success')
    .evaluate((el) => getComputedStyle(el).animationName);
  expect(animationName).toBe('none');
});

test('package managers render grouped by platform with brand icon, name and platform label (DE)', async ({
  page,
}) => {
  await page.goto('/download/');

  const section = page.getByTestId('pkg-managers');
  await section.locator('> summary').click();

  // Short intro explains, in one sentence, what the command does.
  await expect(section).toContainText('installiert WhisPaste');

  const groups = getLivePkgManagersGroupedByPlatform();
  expect(groups.length).toBeGreaterThan(0);

  // Platform group headers render in the fixed Windows → macOS → Linux order
  // supplied by the data-model grouping function (no manual template sort).
  const headerTexts = await section.locator('h4').allTextContents();
  const platformHeaders = headerTexts
    .map((h) => h.trim())
    .filter((h) => Object.values(PLATFORM_LABEL).includes(h));
  expect(platformHeaders).toEqual(groups.map((g) => PLATFORM_LABEL[g.platform]));

  // Every live channel shows its brand icon + brand name + platform label,
  // and keeps its per-channel test anchor.
  for (const group of groups) {
    for (const ch of group.channels) {
      const card = section.getByTestId(`pkg-${ch.id}`);
      await expect(card).toBeVisible();
      await expect(card.locator('svg').first()).toBeVisible();
      await expect(card).toContainText(ch.name);
      await expect(card).toContainText(PLATFORM_LABEL[group.platform]!);
      // Copy button (issue 02) is preserved inside each channel card.
      await expect(card.getByTestId(`pkg-copy-${ch.id}`)).toBeVisible();
    }
  }
});

test('package managers render branded + grouped identically on the EN page', async ({
  page,
}) => {
  await page.goto('/en/download/');

  const section = page.getByTestId('pkg-managers');
  await section.locator('> summary').click();

  await expect(section).toContainText('installs WhisPaste');

  const groups = getLivePkgManagersGroupedByPlatform();
  for (const group of groups) {
    for (const ch of group.channels) {
      const card = section.getByTestId(`pkg-${ch.id}`);
      await expect(card).toContainText(ch.name);
      await expect(card).toContainText(PLATFORM_LABEL[group.platform]!);
    }
  }
});

test('package manager "never used this before?" help is collapsed by default and opens to reveal the manager\'s official setup link (DE)', async ({
  page,
}) => {
  await page.goto('/download/');

  const section = page.getByTestId('pkg-managers');
  await section.locator('> summary').click();

  const groups = getLivePkgManagersGroupedByPlatform();
  for (const group of groups) {
    for (const ch of group.channels) {
      const card = section.getByTestId(`pkg-${ch.id}`);
      const help = card.getByTestId(`pkg-neverused-${ch.id}`);
      const link = card.getByTestId(`pkg-neverused-link-${ch.id}`);

      // Collapsed by default — link not yet visible/interactable.
      await expect(help).not.toHaveJSProperty('open', true);
      await expect(link).not.toBeVisible();

      // Opens on click, revealing a link to this channel's own setup guide.
      await help.locator('summary').click();
      await expect(help).toHaveJSProperty('open', true);
      await expect(link).toBeVisible();
      await expect(link).toHaveAttribute('href', ch.managerInstallUrl);

      // Closes again on a second click of the summary.
      await help.locator('summary').click();
      await expect(help).not.toHaveJSProperty('open', true);
    }
  }
});

test('package manager "never used this before?" help works identically on the EN download page', async ({
  page,
}) => {
  await page.goto('/en/download/');

  const section = page.getByTestId('pkg-managers');
  await section.locator('> summary').click();

  const groups = getLivePkgManagersGroupedByPlatform();
  for (const group of groups) {
    for (const ch of group.channels) {
      const card = section.getByTestId(`pkg-${ch.id}`);
      const help = card.getByTestId(`pkg-neverused-${ch.id}`);
      const link = card.getByTestId(`pkg-neverused-link-${ch.id}`);

      await expect(help).not.toHaveJSProperty('open', true);
      await help.locator('summary').click();
      await expect(link).toBeVisible();
      await expect(link).toHaveAttribute('href', ch.managerInstallUrl);
    }
  }
});

test('package manager section stays scannable at 390px mobile width', async ({
  page,
}) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/download/');

  const section = page.getByTestId('pkg-managers');
  await section.locator('> summary').click();

  const groups = getLivePkgManagersGroupedByPlatform();
  const firstChannel = groups[0]!.channels[0]!;
  const card = section.getByTestId(`pkg-${firstChannel.id}`);
  await expect(card).toBeVisible();
  await expect(card).toContainText(firstChannel.name);

  // The channel card must not overflow the mobile viewport horizontally.
  const box = await card.boundingBox();
  expect(box).not.toBeNull();
  expect(box!.width).toBeLessThanOrEqual(390);
});

test('hero recording mockup renders the final overlay on a canvas (no privacy badge)', async ({ page }) => {
  await page.goto('/');
  await page.locator('.carousel-dot').nth(1).click();

  // The overlay is now a single canvas drawn 1:1 from the SSOT design spec —
  // not a DOM pill. (Issue 10: website = fourth parity platform.)
  const canvas = page.locator('#overlay-canvas');
  await expect(canvas).toBeVisible();

  // AC2: the privacy badge (anti-vocabulary) is gone from markup entirely.
  await expect(page.locator('.overlay-badge-local')).toHaveCount(0);
  await expect(page.locator('.overlay-badge-ai')).toHaveCount(0);
  await expect(page.locator('.overlay-pill')).toHaveCount(0);
  await expect(page.locator('.overlay-wave-bar')).toHaveCount(0);

  // The canvas actually draws something (non-empty backing store).
  const drawn = await canvas.evaluate((el) => {
    const c = el as HTMLCanvasElement;
    const ctx = c.getContext('2d');
    if (!ctx || c.width === 0 || c.height === 0) return false;
    const { data } = ctx.getImageData(0, 0, c.width, c.height);
    for (let i = 3; i < data.length; i += 4) {
      if (data[i] !== 0) return true; // any non-transparent pixel
    }
    return false;
  });
  expect(drawn).toBe(true);
});

test('nav download button keeps its icon after i18n text is applied on load', async ({ page }) => {
  await page.goto('/');

  // Regression: applyLang() used to run el.textContent = ... directly on the
  // <a data-i18n="nav.download"> anchor, wiping the icon <svg> child once the
  // page's inline script ran after SSR paint (the icon "blinked and vanished").
  // The button now holds one platform-labelled variant per OS; data-i18n sits
  // on the inner text <span>s only, so applyLang never touches the icon. Assert
  // the single visible variant keeps its icon after i18n text is applied.
  const navDownloadBtn = page.locator('.nav-download-btn').first();
  await expect(navDownloadBtn.locator('[data-dl-variant]:visible svg')).toBeVisible();
  await expect(navDownloadBtn).toContainText('Download');
});

// The nav Download CTA mirrors the hero: the OS detected before first paint
// (data-os on <html>) swaps the button to a platform-labelled variant via CSS,
// with the generic "Download" as the unknown-OS fallback. We drive data-os
// directly (the CSS reacts instantly) instead of spoofing the UA, so the test
// asserts the pure attribute → visible-variant contract for both navs and langs.
const NAV_DL_LABELS = {
  de: { macos: 'Für macOS', windows: 'Für Windows', linux: 'Für Ubuntu' },
  en: { macos: 'For macOS', windows: 'For Windows', linux: 'For Ubuntu' },
} as const;

async function assertNavDownloadAdaptsToOs(
  page: Page,
  btn: Locator,
  labels: { macos: string; windows: string; linux: string },
) {
  for (const os of ['macos', 'windows', 'linux'] as const) {
    await page.evaluate((o) => {
      document.documentElement.dataset.os = o;
    }, os);
    const variant = btn.locator(`[data-dl-variant="${os}"]`);
    await expect(variant).toBeVisible();
    await expect(variant).toContainText(labels[os]); // localized platform label
    await expect(variant).toContainText('Download'); // sr-only prefix for a11y
    await expect(variant.locator('svg')).toBeVisible(); // brand glyph, not wiped
    await expect(btn.locator('[data-dl-variant="generic"]')).toBeHidden();
  }
  // Unknown / missing OS → generic "Download" fallback (current behaviour).
  await page.evaluate(() => {
    delete document.documentElement.dataset.os;
  });
  const generic = btn.locator('[data-dl-variant="generic"]');
  await expect(generic).toBeVisible();
  await expect(generic).toContainText('Download');
  await expect(btn.locator('[data-dl-variant="macos"]')).toBeHidden();
}

test('desktop nav download button adapts label + icon to detected OS (DE)', async ({ page }) => {
  await page.goto('/');
  await assertNavDownloadAdaptsToOs(page, page.locator('.nav-download-btn').first(), NAV_DL_LABELS.de);
});

test('desktop nav download button adapts label + icon to detected OS (EN)', async ({ page }) => {
  await page.goto('/en/');
  await assertNavDownloadAdaptsToOs(page, page.locator('.nav-download-btn').first(), NAV_DL_LABELS.en);
});

test('mobile nav download button adapts label + icon to detected OS (DE)', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/');
  await page.locator('#mobileMenuBtn').click();
  await assertNavDownloadAdaptsToOs(page, page.locator('#mobileMenu .nav-download-btn'), NAV_DL_LABELS.de);
});

test('mobile nav download button adapts label + icon to detected OS (EN)', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/en/');
  await page.locator('#mobileMenuBtn').click();
  await assertNavDownloadAdaptsToOs(page, page.locator('#mobileMenu .nav-download-btn'), NAV_DL_LABELS.en);
});
