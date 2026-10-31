import { expect, test } from '@playwright/test';

// The hero visual is the page's one "how it works": an e-mail window that
// plays hotkey → speak → text. The finished text is the first frame (readable
// without JS, LCP), the step bar below lets the visitor pick a step.
for (const { path, body, step1 } of [
  { path: '/', body: /Entwurf heute Nachmittag/, step1: 'Hotkey drücken' },
  { path: '/en/', body: /draft this afternoon/, step1: 'Press' },
]) {
  test(`hero shows the finished e-mail example first (${path})`, async ({ page }) => {
    await page.goto(path);
    const hero = page.getByTestId('hero');
    const example = hero.getByTestId('hero-example');
    await expect(example).toBeVisible();
    await expect(example).toHaveAttribute('data-step', '3');
    await expect(example).toContainText(body);
    await expect(hero.locator('video')).toHaveCount(0);

    // Decorative window: no focusable controls inside the illustration.
    await expect(example.getByRole('img').locator('a, button, input, textarea')).toHaveCount(0);
    await expect(example.locator('.hx-overlay')).toHaveAttribute('aria-hidden', 'true');

    // Three labelled steps, the finished one open; the nav anchor lands here.
    await expect(example.getByTestId('hero-step-1')).toContainText(step1);
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
  // Empty field, caret at its start; the text keeps its room (no jump).
  await expect(text).toHaveCSS('visibility', 'hidden');
  const caret = await example.locator('.hx-caret').boundingBox();
  const editor = await example.locator('.hx-editor').boundingBox();
  expect(caret!.x - editor!.x).toBeLessThan(40);
  expect(caret!.y - editor!.y).toBeLessThan(40);
  await expect(overlay).toHaveCSS('opacity', '0');

  await example.getByTestId('hero-step-2').click();
  await expect(example).toHaveAttribute('data-pill', 'on');
  await expect(overlay).toHaveCSS('opacity', '1');
  await expect(overlay.locator('canvas')).toBeVisible();

  // A click hands control to the visitor: no autoplay afterwards.
  await expect(example).not.toHaveAttribute('data-autoplay', /.*/);
  await example.getByTestId('hero-step-3').click();
  await expect(text).toHaveCSS('visibility', 'visible');
});

test('hero steps autoplay from the finished text to the hotkey', async ({ page }) => {
  await page.goto('/en/');
  const example = page.getByTestId('hero-example');
  await expect(example).toHaveAttribute('data-autoplay', '');
  // Off screen the story waits at its first frame.
  await page.waitForTimeout(3000);
  if (await example.getAttribute('data-paused') !== null) {
    await expect(example).toHaveAttribute('data-step', '3');
  }
  await example.scrollIntoViewIfNeeded();
  // Step 3 runs ~2.4 s, then the story starts over at the hotkey.
  await expect(example.getByTestId('hero-step-1')).toHaveAttribute('aria-pressed', 'true', { timeout: 4000 });
  // The whole loop stays short: hotkey + speaking take ~4 s together.
  await expect(example.getByTestId('hero-step-2')).toHaveAttribute('aria-pressed', 'true', { timeout: 2000 });
  await expect(example).toHaveAttribute('data-pill', 'on');
  await expect(example.getByTestId('hero-step-3')).toHaveAttribute('aria-pressed', 'true', { timeout: 3500 });
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
