import { expect, test } from '@playwright/test';

test.describe('UseCaseCards', () => {
  test('section is present on DE landing page with 3 cards', async ({ page }) => {
    await page.goto('/');
    const section = page.locator('#use-cases');
    await section.scrollIntoViewIfNeeded();
    await expect(section).toBeVisible();
    const cards = section.locator('a.use-case-card');
    await expect(cards).toHaveCount(3);
  });

  test('section is present on EN landing page with 3 cards', async ({ page }) => {
    await page.goto('/en/');
    const section = page.locator('#use-cases');
    await section.scrollIntoViewIfNeeded();
    await expect(section).toBeVisible();
    const cards = section.locator('a.use-case-card');
    await expect(cards).toHaveCount(3);
  });

  test('DE cards link to /use-cases/... slugs (not /en/use-cases/)', async ({ page }) => {
    await page.goto('/');
    const section = page.locator('#use-cases');
    const cards = section.locator('a.use-case-card');

    const hrefs = await cards.evaluateAll((els) =>
      els.map((el) => (el as HTMLAnchorElement).getAttribute('href') ?? ''),
    );

    expect(hrefs).toHaveLength(3);
    for (const href of hrefs) {
      expect(href).toMatch(/^\/use-cases\//);
      expect(href).not.toContain('/en/');
    }
    // Verify exact slugs
    expect(hrefs).toContain('/use-cases/programmierer/');
    expect(hrefs).toContain('/use-cases/studierende/');
    expect(hrefs).toContain('/use-cases/vielschreiber/');
  });

  test('EN cards link to /en/use-cases/... slugs', async ({ page }) => {
    await page.goto('/en/');
    const section = page.locator('#use-cases');
    const cards = section.locator('a.use-case-card');

    const hrefs = await cards.evaluateAll((els) =>
      els.map((el) => (el as HTMLAnchorElement).getAttribute('href') ?? ''),
    );

    expect(hrefs).toHaveLength(3);
    for (const href of hrefs) {
      expect(href).toMatch(/^\/en\/use-cases\//);
    }
    // Verify exact slugs
    expect(hrefs).toContain('/en/use-cases/programmer/');
    expect(hrefs).toContain('/en/use-cases/students/');
    expect(hrefs).toContain('/en/use-cases/everyday/');
  });

  test('cards are natively keyboard-focusable (anchor elements with href)', async ({ page }) => {
    await page.goto('/');
    const section = page.locator('#use-cases');
    const cards = section.locator('a.use-case-card');

    // All cards must be <a> elements with an href — natively in tab order
    const tagNames = await cards.evaluateAll((els) =>
      els.map((el) => el.tagName.toLowerCase()),
    );
    for (const tag of tagNames) {
      expect(tag).toBe('a');
    }

    const hasHref = await cards.evaluateAll((els) =>
      els.map((el) => (el as HTMLAnchorElement).hasAttribute('href')),
    );
    for (const h of hasHref) {
      expect(h).toBe(true);
    }
  });

  test('first card receives focus and shows a visible focus ring', async ({ page }) => {
    await page.goto('/');
    const section = page.locator('#use-cases');
    await section.scrollIntoViewIfNeeded();

    const firstCard = section.locator('a.use-case-card').first();

    // Programmatic focus — in Chromium this activates :focus-visible
    await firstCard.focus();
    await expect(firstCard).toBeFocused();

    // The global CSS rule `a:focus-visible { outline: 2px solid … }` must apply.
    // We read computed outline-width; expect a positive value (Chromium activates
    // :focus-visible on programmatic focus when no prior mouse interaction).
    const outlineWidth = await firstCard.evaluate((el) =>
      getComputedStyle(el).outlineWidth,
    );
    const widthPx = parseFloat(outlineWidth);
    expect(widthPx).toBeGreaterThan(0);
  });

  test('all three cards are focusable in DOM order via Tab', async ({ page }) => {
    await page.goto('/');
    const section = page.locator('#use-cases');
    await section.scrollIntoViewIfNeeded();

    const cards = section.locator('a.use-case-card');
    const firstCard = cards.nth(0);
    const secondCard = cards.nth(1);
    const thirdCard = cards.nth(2);

    // Focus first card then Tab through the rest
    await firstCard.focus();
    await expect(firstCard).toBeFocused();

    await page.keyboard.press('Tab');
    await expect(secondCard).toBeFocused();

    await page.keyboard.press('Tab');
    await expect(thirdCard).toBeFocused();
  });

  // WCAG 2.5.3 (#1630): no aria-label that hides the visible text; the
  // accessible name starts with the visible card title, in every language.
  for (const path of ['/', '/en/', '/es/', '/pt/', '/it/', '/ru/', '/zh/', '/fr/']) {
    test(`cards are named by their visible title on ${path}`, async ({ page }) => {
      await page.goto(path);
      const cards = page.locator('#use-cases a.use-case-card');
      await expect(cards).toHaveCount(3);
      for (const card of await cards.all()) {
        expect(await card.getAttribute('aria-label')).toBeNull();
        const title = (await card.locator('.use-case-card__title').innerText()).trim();
        const escaped = title.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
        await expect(card).toHaveAccessibleName(new RegExp(`^${escaped}`));
      }
    });
  }
});
