import { expect, test } from '@playwright/test';

test.describe('WorkflowSelector', () => {
  test('section is present on DE landing page with 3 cards', async ({ page }) => {
    await page.goto('/');
    const section = page.locator('#workflow-selector');
    await section.scrollIntoViewIfNeeded();
    await expect(section).toBeVisible();
    const cards = section.locator('a.workflow-card');
    await expect(cards).toHaveCount(3);
  });

  test('section is present on EN landing page with 3 cards', async ({ page }) => {
    await page.goto('/en/');
    const section = page.locator('#workflow-selector');
    await section.scrollIntoViewIfNeeded();
    await expect(section).toBeVisible();
    const cards = section.locator('a.workflow-card');
    await expect(cards).toHaveCount(3);
  });

  test('DE cards link to /use-cases/... slugs (not /en/use-cases/)', async ({ page }) => {
    await page.goto('/');
    const section = page.locator('#workflow-selector');
    const cards = section.locator('a.workflow-card');

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
    const section = page.locator('#workflow-selector');
    const cards = section.locator('a.workflow-card');

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
    const section = page.locator('#workflow-selector');
    const cards = section.locator('a.workflow-card');

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
    const section = page.locator('#workflow-selector');
    await section.scrollIntoViewIfNeeded();

    const firstCard = section.locator('a.workflow-card').first();

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
    const section = page.locator('#workflow-selector');
    await section.scrollIntoViewIfNeeded();

    const cards = section.locator('a.workflow-card');
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

  test('cards have aria-label attributes', async ({ page }) => {
    await page.goto('/');
    const cards = page.locator('#workflow-selector a.workflow-card');

    const ariaLabels = await cards.evaluateAll((els) =>
      els.map((el) => el.getAttribute('aria-label') ?? ''),
    );
    for (const label of ariaLabels) {
      expect(label.length).toBeGreaterThan(0);
    }
  });

  test('section is placed after the app-paste-demo explanation in DOM', async ({ page }) => {
    await page.goto('/');

    // Verify DOM order: #app-paste-demo (the single mechanic explanation —
    // the former #how-it-works section was removed) appears before
    // #workflow-selector.
    const order = await page.evaluate(() => {
      const demo = document.querySelector('#app-paste-demo');
      const selector = document.querySelector('#workflow-selector');
      if (!demo || !selector) return null;
      const pos = demo.compareDocumentPosition(selector);
      // DOCUMENT_POSITION_FOLLOWING = 4
      return (pos & 4) === 4;
    });
    expect(order).toBe(true);
  });
});
