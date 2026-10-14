import { expect, test } from '@playwright/test';

// The hero visual is a static, finished e-mail example: readable on the first
// frame, no media download, and a link down to the step-by-step demo.
for (const { path, body } of [
  { path: '/', body: /Entwurf heute Nachmittag/ },
  { path: '/en/', body: /draft this afternoon/ },
]) {
  test(`hero shows the static e-mail example (${path})`, async ({ page }) => {
    await page.goto(path);
    const hero = page.getByTestId('hero');
    const example = hero.getByTestId('hero-example');
    await expect(example).toBeVisible();
    await expect(example).toContainText(body);
    await expect(hero.locator('video')).toHaveCount(0);
    await expect(page.locator('head link[rel="preload"][as="image"][href^="/videos/"]')).toHaveCount(0);

    // Decorative window: no focusable controls inside the illustration.
    await expect(example.getByRole('img').locator('a, button, input, textarea')).toHaveCount(0);

    // The app's recording overlay plays on top of the editor (decorative).
    const overlay = example.locator('.hx-overlay');
    await expect(overlay).toHaveAttribute('aria-hidden', 'true');
    await expect(overlay.locator('canvas')).toBeVisible();

    // The hero hands off directly to the step-by-step demo.
    const nextId = await hero.evaluate((el) => {
      let next = el.nextElementSibling;
      while (next && next.tagName !== 'SECTION') next = next.nextElementSibling;
      return next?.id ?? '';
    });
    expect(nextId).toBe('app-paste-demo');
    await expect(example.getByTestId('hero-demo-link')).toHaveAttribute('href', '#app-paste-demo');
  });
}
