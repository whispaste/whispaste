import { expect, test, type Page } from '@playwright/test';

/**
 * visitor-platform.spec.ts: the visitor's own OS decides what the start page
 * and the download page show first (ticket 19).
 *
 * - Hero keycaps: ⌘ ⇧ D on macOS, Ctrl Shift D on Windows and Linux, neutral without JS.
 * - Hero store button: the visitor's platform only, no other store next to it.
 * - Download page: the matching OS card and its free route come first; the
 *   other two systems sit behind "Andere Plattformen".
 *
 * navigator.userAgentData is removed so the classic UA regex decides, which
 * keeps the result independent of the runner's real platform.
 */

const MAC_UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15';
const WIN_UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';
const LINUX_UA = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

async function hideClientHints(page: Page) {
  await page.addInitScript(() => {
    Object.defineProperty(Navigator.prototype, 'userAgentData', { get: () => undefined });
  });
}

test.describe('macOS visitor', () => {
  test.use({ userAgent: MAC_UA, viewport: { width: 1440, height: 900 } });

  test('hero keycaps show the Mac modifier and the Mac store button is the only store', async ({ page }) => {
    await hideClientHints(page);
    await page.goto('/en/');
    await expect(page.locator('html')).toHaveAttribute('data-os', 'macos');
    expect(await page.getByTestId('hero-sticker-keys').locator('kbd').allInnerTexts()).toEqual(['⌘', '⇧', 'D']);

    const hero = page.getByTestId('hero');
    await expect(hero.locator('[data-platform-btn="macos"]').first()).toBeVisible();
    await expect(hero.locator('[data-platform-btn="windows"]').first()).toBeHidden();
  });

  test('download page: the Mac card comes first, Windows is behind "Andere Plattformen"', async ({ page }) => {
    await hideClientHints(page);
    await page.goto('/en/download/');
    const toggle = page.getByTestId('other-platforms-toggle');
    await expect(toggle).toBeVisible();
    await expect(toggle).toHaveAttribute('aria-expanded', 'false');
    await expect(page.locator('[data-platform-card="windows"]')).toBeHidden();
    await expect(page.locator('[data-platform-card="windows-free"]')).toBeHidden();
    await expect(page.locator('[data-platform-card="macos"]')).toBeVisible();
    await expect(page.locator('[data-platform-card="macos-free"]')).toBeVisible();

    const macY = (await page.locator('[data-platform-card="macos"]').boundingBox())!.y;
    const freeY = (await page.locator('[data-platform-card="macos-free"]').boundingBox())!.y;
    const toggleY = (await toggle.boundingBox())!.y;
    expect(macY).toBeLessThan(freeY);
    expect(freeY).toBeLessThan(toggleY);

    await toggle.click();
    await expect(toggle).toHaveAttribute('aria-expanded', 'true');
    await expect(page.locator('[data-platform-card="windows"]')).toBeVisible();
    const winY = (await page.locator('[data-platform-card="windows"]').boundingBox())!.y;
    expect(winY).toBeGreaterThan((await toggle.boundingBox())!.y);
  });
});

test.describe('Windows visitor', () => {
  test.use({ userAgent: WIN_UA, viewport: { width: 1440, height: 900 } });

  test('hero keycaps show Ctrl Shift D and the Microsoft Store button is the only store', async ({ page }) => {
    await hideClientHints(page);
    await page.goto('/en/');
    await expect(page.locator('html')).toHaveAttribute('data-os', 'windows');
    expect(await page.getByTestId('hero-sticker-keys').locator('kbd').allInnerTexts()).toEqual(['Ctrl', 'Shift', 'D']);

    const hero = page.getByTestId('hero');
    await expect(hero.locator('[data-platform-btn="windows"]').first()).toBeVisible();
    await expect(hero.locator('[data-platform-btn="macos"]').first()).toBeHidden();
  });

  test('download page: the Windows card comes first and the Mac card is behind the toggle', async ({ page }) => {
    await hideClientHints(page);
    await page.goto('/en/download/');
    await expect(page.locator('[data-platform-card="windows"]')).toBeVisible();
    await expect(page.locator('[data-platform-card="macos"]')).toBeHidden();
    await expect(page.getByTestId('other-platforms-toggle')).toBeVisible();
    await page.getByTestId('other-platforms-toggle').click();
    await expect(page.locator('[data-platform-card="macos"]')).toBeVisible();
  });
});

test.describe('Linux visitor', () => {
  test.use({ userAgent: LINUX_UA, viewport: { width: 1440, height: 900 } });

  test('hero keycaps show Ctrl Shift D', async ({ page }) => {
    await hideClientHints(page);
    await page.goto('/en/');
    await expect(page.locator('html')).toHaveAttribute('data-os', 'linux');
    expect(await page.getByTestId('hero-sticker-keys').locator('kbd').allInnerTexts()).toEqual(['Ctrl', 'Shift', 'D']);
  });

  test('download page: the Linux card comes first and the other systems sit behind the toggle', async ({ page }) => {
    await hideClientHints(page);
    await page.goto('/en/download/');
    const toggle = page.getByTestId('other-platforms-toggle');
    await expect(page.locator('[data-platform-card="linux"]')).toBeVisible();
    await expect(toggle).toBeVisible();
    await expect(page.locator('[data-platform-card="windows"]')).toBeHidden();
    await expect(page.locator('[data-platform-card="macos"]')).toBeHidden();

    const linuxY = (await page.locator('[data-platform-card="linux"]').boundingBox())!.y;
    const toggleY = (await toggle.boundingBox())!.y;
    expect(linuxY).toBeLessThan(toggleY);

    await toggle.click();
    await expect(page.locator('[data-platform-card="windows"]')).toBeVisible();
  });
});

test.describe('no JavaScript', () => {
  test.use({ javaScriptEnabled: false, viewport: { width: 390, height: 844 } });

  test('keycaps show the neutral label and the download page shows every card', async ({ page }) => {
    await page.goto('/en/');
    expect(await page.getByTestId('hero-sticker-keys').locator('kbd').allInnerTexts()).toEqual(['Ctrl/⌘', 'Shift', 'D']);

    await page.goto('/en/download/');
    await expect(page.getByTestId('other-platforms-toggle')).toBeHidden();
    await expect(page.locator('[data-platform-card="windows"]')).toBeVisible();
    await expect(page.locator('[data-platform-card="macos"]')).toBeVisible();
    await expect(page.locator('[data-platform-card="linux"]')).toBeVisible();
  });
});
