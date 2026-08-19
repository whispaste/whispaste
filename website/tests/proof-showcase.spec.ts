import { expect, test } from '@playwright/test';

/**
 * ProofShowcase — the "real screen recordings" section between AppPasteDemo
 * and UseCaseCards. Covers the lazy-hydration contract (only the active
 * beat's clip is loaded), the tile switching semantics (aria-pressed), and
 * the reduced-motion still-variant swap that mirrors the in-app onboarding
 * (`welcome_step.dart`): animated WebP cannot be paused, so reduce-motion
 * must load a genuinely static file.
 */
test.describe('ProofShowcase', () => {
  test('renders three tiles beside one stage, first beat active, others not fetched', async ({
    page,
  }) => {
    await page.goto('/');
    const section = page.locator('#proof');
    await section.scrollIntoViewIfNeeded();
    await expect(section).toBeVisible();

    const tiles = section.locator('.proof-tile');
    await expect(tiles).toHaveCount(3);
    await expect(tiles.nth(0)).toHaveAttribute('aria-pressed', 'true');
    await expect(tiles.nth(1)).toHaveAttribute('aria-pressed', 'false');

    const medias = section.locator('.proof-media');
    await expect(medias.nth(0)).toHaveClass(/is-active/);

    // Lazy contract: beats 2/3 must not carry a live src before activation.
    for (const i of [1, 2]) {
      const img = medias.nth(i).locator('img');
      await expect(img).not.toHaveAttribute('src', /.+/);
      await expect(img).toHaveAttribute('data-src', /beat_\d_loop_dark\.webp/);
    }
  });

  test('section is present on the EN landing page with EN copy', async ({
    page,
  }) => {
    await page.goto('/en/');
    const section = page.locator('#proof');
    await section.scrollIntoViewIfNeeded();
    await expect(section).toBeVisible();
    await expect(section.locator('.proof-tile')).toHaveCount(3);
    await expect(section).toContainText('Speak. It lands.');
  });

  test('clicking a tile hydrates and activates its beat', async ({ page }) => {
    await page.goto('/');
    const section = page.locator('#proof');
    await section.scrollIntoViewIfNeeded();

    const tiles = section.locator('.proof-tile');
    await tiles.nth(1).click();

    await expect(tiles.nth(1)).toHaveAttribute('aria-pressed', 'true');
    await expect(tiles.nth(0)).toHaveAttribute('aria-pressed', 'false');

    const medias = section.locator('.proof-media');
    await expect(medias.nth(1)).toHaveClass(/is-active/);
    await expect(medias.nth(0)).not.toHaveClass(/is-active/);
    await expect(medias.nth(1).locator('img')).toHaveAttribute(
      'src',
      /beat_2_loop_dark\.webp/,
    );
  });

  test('reduced motion renders the still variant instead of the loop', async ({
    page,
  }) => {
    await page.emulateMedia({ reducedMotion: 'reduce' });
    await page.goto('/');
    const section = page.locator('#proof');
    await section.scrollIntoViewIfNeeded();

    const activeImg = section.locator('.proof-media.is-active img');
    await expect
      .poll(async () => activeImg.evaluate((el) => (el as HTMLImageElement).currentSrc))
      .toMatch(/beat_1_still_dark\.webp/);
  });

  test('section stays usable at 390px mobile width', async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await page.goto('/');
    const section = page.locator('#proof');
    await section.scrollIntoViewIfNeeded();
    await expect(section).toBeVisible();

    // No horizontal page overflow introduced by the stage/tiles.
    const overflow = await page.evaluate(
      () => document.documentElement.scrollWidth - document.documentElement.clientWidth,
    );
    expect(overflow).toBeLessThanOrEqual(0);

    const tiles = section.locator('.proof-tile');
    await tiles.nth(2).click();
    await expect(tiles.nth(2)).toHaveAttribute('aria-pressed', 'true');
  });
});
