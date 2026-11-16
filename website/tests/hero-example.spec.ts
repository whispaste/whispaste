import { expect, test } from '@playwright/test';

// The hero visual is the page's one "how it works": an e-mail window that
// plays hotkey → speak → text. The finished text is the first frame (readable
// without JS, LCP), the step bar below lets the visitor pick a step.
for (const path of ['/', '/en/'] as const) {
  test(`hero shows the finished e-mail example first (${path})`, async ({ page }) => {
    await page.goto(path);
    const hero = page.getByTestId('hero');
    const example = hero.getByTestId('hero-example');
    await expect(example).toBeVisible();
    await expect(example).toHaveAttribute('data-step', '3');
    await expect(hero.locator('video')).toHaveCount(0);

    // Decorative window: no focusable controls inside the illustration.
    await expect(example.getByRole('img').locator('a, button, input, textarea')).toHaveCount(0);
    await expect(example.locator('.hx-overlay')).toHaveAttribute('aria-hidden', 'true');

    // Three labelled steps, the finished one open; the nav anchor lands here.
    await expect(example.getByTestId('hero-step-3')).toHaveAttribute('aria-pressed', 'true');
    await expect(hero.locator('#how-it-works')).toHaveCount(1);
    await expect(page.locator('#app-paste-demo')).toHaveCount(0);
  });
}

test('hero steps: hotkey waits with an empty field, speaking shows the pill, then the text lands', async ({ page }) => {
  await page.goto('/en/');
  const example = page.getByTestId('hero-example');
  const text = example.locator('.hx-body-text');
  const overlay = example.locator('.hx-overlay');

  await example.getByTestId('hero-step-1').click();
  await expect(example.getByTestId('hero-step-1')).toHaveAttribute('aria-pressed', 'true');
  await expect(example.getByTestId('hero-step-3')).toHaveAttribute('aria-pressed', 'false');
  await expect(page.getByTestId('hero-stage')).toHaveAttribute('data-step', '1');
  // Empty field: the text stays hidden until it lands.
  await expect(text).toHaveCSS('visibility', 'hidden');

  await example.getByTestId('hero-step-2').click();
  await expect(example).toHaveAttribute('data-pill', 'on');
  await expect(overlay.locator('canvas')).toBeVisible();

  // A click hands control to the visitor: no autoplay afterwards.
  await expect(example).not.toHaveAttribute('data-autoplay', /.*/);
  await example.getByTestId('hero-step-3').click();
  await expect(text).toHaveCSS('visibility', 'visible');
});

test.describe('reduced motion', () => {
  test.use({ contextOptions: { reducedMotion: 'reduce' } });
  test('hero holds the finished text with the still pill', async ({ page }) => {
    await page.goto('/en/');
    const example = page.getByTestId('hero-example');
    await expect(example).not.toHaveAttribute('data-autoplay', /.*/);
    await expect(example).toHaveAttribute('data-pill', 'on');
    await page.waitForTimeout(4000);
    await expect(example.getByTestId('hero-step-3')).toHaveAttribute('aria-pressed', 'true');
  });
});
