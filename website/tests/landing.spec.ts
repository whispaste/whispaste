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

test('language menu switches the landing page between locales', async ({ page }) => {
  await page.goto('/');

  await page.getByTestId('lang-switch').locator('summary').click();
  await page.getByTestId('lang-switch-en').click();
  await page.waitForURL(/\/en\/?$/);
  await expect(page.locator('html')).toHaveAttribute('lang', 'en');

  await page.getByTestId('lang-switch').locator('summary').click();
  await page.getByTestId('lang-switch-de').click();
  await page.waitForURL(/\/$/);
});

test('FAQ section is visible and has accordion items', async ({ page }) => {
  await page.goto('/');

  const faq = page.locator('#faq');
  await faq.scrollIntoViewIfNeeded();
  await expect(faq).toBeVisible();
  await expect(faq.locator('details').first()).toBeVisible();
});

test('legal pages load without 404s', async ({ page }) => {
  await page.goto('/datenschutz/');
  await expect(page.locator('#pageTitle')).toBeVisible();

  await page.goto('/impressum/');
  await expect(page.locator('#pageTitle')).toBeVisible();
});

test('download page has the GitHub free download button', async ({ page }) => {
  await page.goto('/download/');
  // GitHub free download section — Windows button has data-testid="github-windows-button"
  await expect(page.getByTestId('github-windows-button')).toBeVisible();
});

test('Linux section offers a direct AppImage/.deb download, with build-from-source as a collapsed secondary option', async ({
  page,
}) => {
  await page.goto('/download/');

  // With a known OS (here: a Mac runner) other systems sit behind
  // "Andere Plattformen" (ticket 19); open it like a visitor would.
  const otherToggle = page.getByTestId('other-platforms-toggle');
  if ((await otherToggle.isVisible()) && (await otherToggle.getAttribute('aria-expanded')) !== 'true') {
    await otherToggle.click();
  }

  // Direct downloads are visible without any further interaction — no build required.
  const appimageBtn = page.getByTestId('linux-appimage-button');
  await expect(appimageBtn).toBeVisible();
  await expect(appimageBtn).toHaveAttribute('href', /WhisPaste-linux-x64\.AppImage$/);
  const debBtn = page.getByTestId('linux-deb-button');
  await expect(debBtn).toBeVisible();
  await expect(debBtn).toHaveAttribute('href', /WhisPaste-linux-x64\.deb$/);

  // Build-from-source is demoted to a collapsed secondary option.
  const sourceBuild = page.getByTestId('linux-source-build');
  const githubBtn = page.getByTestId('linux-github-button');
  await expect(githubBtn).toBeHidden();
  await sourceBuild.locator('> summary').click();
  await expect(githubBtn).toBeVisible();
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

  // Screen readers get an announcement via a polite live region.
  const status = page.locator('#pkg-copy-status');
  await expect(status).toHaveAttribute('aria-live', 'polite');
  await expect(status).not.toBeEmpty();

  // Feedback reverts after the timeout.
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

  const groups = getLivePkgManagersGroupedByPlatform();
  expect(groups.length).toBeGreaterThan(0);

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

test('recording overlay renders on a canvas in the hero (no privacy badge)', async ({ page }) => {
  await page.goto('/');
  // The hero shows a static e-mail example; the former three-scene carousel
  // mockup (and its own overlay canvas) is gone.
  await expect(page.locator('.carousel-dot')).toHaveCount(0);
  await expect(page.locator('#overlay-canvas')).toHaveCount(0);

  // The overlay is a single canvas drawn 1:1 from the SSOT design spec —
  // not a DOM pill. (Issue 10: website = fourth parity platform.)
  const canvas = page.locator('#how-it-works .hx-overlay-canvas');
  await page.getByTestId('hero-step-2').click();
  await expect(canvas).toBeVisible();

  // AC2: the privacy badge (anti-vocabulary) is gone from markup entirely.
  await expect(page.locator('.overlay-badge-local')).toHaveCount(0);
  await expect(page.locator('.overlay-badge-ai')).toHaveCount(0);
  await expect(page.locator('.overlay-pill')).toHaveCount(0);
  await expect(page.locator('.overlay-wave-bar')).toHaveCount(0);
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
});

// The nav Download CTA mirrors the hero: the OS detected before first paint
// (data-os on <html>) swaps the button to a platform-labelled variant via CSS,
// with the generic "Download" as the unknown-OS fallback. We drive data-os
// directly (the CSS reacts instantly) instead of spoofing the UA, so the test
// asserts the pure attribute → visible-variant contract for both navs and langs.
async function assertNavDownloadAdaptsToOs(page: Page, btn: Locator) {
  for (const os of ['macos', 'windows', 'linux'] as const) {
    await page.evaluate((o) => {
      document.documentElement.dataset.os = o;
    }, os);
    const variant = btn.locator(`[data-dl-variant="${os}"]`);
    await expect(variant).toBeVisible();
    await expect(variant.locator('svg')).toBeVisible(); // brand glyph, not wiped
    await expect(btn.locator('[data-dl-variant="generic"]')).toBeHidden();
  }
  // Unknown / missing OS → generic "Download" fallback (current behaviour).
  await page.evaluate(() => {
    delete document.documentElement.dataset.os;
  });
  const generic = btn.locator('[data-dl-variant="generic"]');
  await expect(generic).toBeVisible();
  await expect(btn.locator('[data-dl-variant="macos"]')).toBeHidden();
}

test('desktop nav download button adapts label + icon to detected OS (DE)', async ({ page }) => {
  await page.goto('/');
  await assertNavDownloadAdaptsToOs(page, page.locator('.nav-download-btn').first());
});

test('desktop nav download button adapts label + icon to detected OS (EN)', async ({ page }) => {
  await page.goto('/en/');
  await assertNavDownloadAdaptsToOs(page, page.locator('.nav-download-btn').first());
});

test('mobile nav download button adapts label + icon to detected OS (DE)', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/');
  await page.locator('#mobileMenuBtn').click();
  await assertNavDownloadAdaptsToOs(page, page.locator('#mobileMenu .nav-download-btn'));
});

test('mobile nav download button adapts label + icon to detected OS (EN)', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/en/');
  await page.locator('#mobileMenuBtn').click();
  await assertNavDownloadAdaptsToOs(page, page.locator('#mobileMenu .nav-download-btn'));
});

// Smart Mode can rewrite transcripts on request, so the hero demo no longer
// promises "transcribed, not rewritten"; and "free" always names its channel
// (GitHub), because the Store versions are paid. Since #1949 (D-005) the
// free route sits in the price block, not next to the hero's store buttons.
for (const { path, freeOnGitHub } of [
  { path: '/', freeOnGitHub: 'kostenlos auf GitHub' },
  { path: '/en/', freeOnGitHub: 'free on GitHub' },
]) {
  test(`${path}: no "not rewritten" chip, free means free on GitHub`, async ({ page }) => {
    await page.goto(path);
    await expect(page.locator('[data-i18n="appdemo.noAiEdit"]')).toHaveCount(0);
    await expect(page).toHaveTitle(new RegExp(freeOnGitHub, 'i'));
    await expect(page.getByTestId('pricing-free')).toContainText(new RegExp(freeOnGitHub, 'i'));
    await expect(page.getByTestId('hero-secondary-cta')).not.toContainText(/github|kostenlos|free/i);
  });
}

// #1949: the compact differences block follows the feature highlights (the
// original order above it stays), has no buy button of its own and links to
// the full block (maintainer 2026-11-19).
for (const { path, more } of [
  { path: '/', more: '/whisper-desktop/#differences' },
  { path: '/en/', more: '/en/whisper-desktop/#differences' },
]) {
  test(`${path}: compact differences block after the feature highlights`, async ({ page }) => {
    await page.goto(path);
    const prev = await page.getByTestId('home-differences').evaluate((el) => el.previousElementSibling?.id);
    expect(prev).toBe('features');
    const block = page.getByTestId('differences');
    await expect(block.getByTestId('store-button')).toHaveCount(0);
    await expect(block.locator('li')).toHaveCount(2);
    await expect(block.locator('img')).toHaveCount(0);
    await expect(block.getByTestId('differences-more')).toHaveAttribute('href', more);
    await expect(block.locator('a[href*="github.com"]:visible')).toHaveCount(0);
  });
}
