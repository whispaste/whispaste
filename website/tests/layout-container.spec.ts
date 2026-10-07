import { expect, test } from '@playwright/test';

// One shared container (`.wp-container`, global.css) frames the floating nav
// pill and every section: the nav must never be narrower than the content,
// the content never wider than the nav, and nothing may scroll sideways.
const WIDTHS = [390, 768, 1024, 1440, 1920] as const;

for (const path of ['/', '/en/']) {
  for (const width of WIDTHS) {
    test(`${path} @${width}px: nav and content share one frame`, async ({ page }) => {
      await page.setViewportSize({ width, height: 900 });
      // Layout only needs DOM + fonts; skipping the full load event keeps the
      // ten-width matrix fast and stable on a busy machine.
      await page.goto(path, { waitUntil: 'domcontentloaded' });
      await page.evaluate(() => document.fonts.ready);

      const nav = await page.locator('#site-nav .nav-pill').boundingBox();
      expect(nav).not.toBeNull();

      // The hero frame matches the nav pill edge for edge.
      const hero = await page.getByTestId('hero').locator(':scope > .wp-container').boundingBox();
      expect(hero).not.toBeNull();
      expect(Math.abs(hero!.x - nav!.x)).toBeLessThanOrEqual(1);
      expect(Math.abs(hero!.width - nav!.width)).toBeLessThanOrEqual(1);

      // No section content box pokes out past the nav's outer edges.
      const boxes = await page.locator('main .wp-container').evaluateAll((els) =>
        els.map((el) => {
          const r = el.getBoundingClientRect();
          return { left: r.left, right: r.right };
        }),
      );
      expect(boxes.length).toBeGreaterThan(5);
      for (const b of boxes) {
        expect(b.left).toBeGreaterThanOrEqual(nav!.x - 1);
        expect(b.right).toBeLessThanOrEqual(nav!.x + nav!.width + 1);
      }

      // Mobile gutter is 16 px.
      if (width < 640) expect(Math.round(nav!.x)).toBe(16);

      // No horizontal page scroll, and the nav's own items fit inside it.
      const overflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth);
      expect(overflow).toBe(false);
      const navOverflow = await page
        .locator('#site-nav .nav-pill')
        .evaluate((el) => el.scrollWidth > el.clientWidth + 1);
      expect(navOverflow).toBe(false);

      // Section links collapse into the menu button below lg.
      const menuBtn = page.locator('#mobileMenuBtn');
      if (width < 1024) await expect(menuBtn).toBeVisible();
      else await expect(menuBtn).toBeHidden();
    });
  }
}

test('hero film dominates the split layout on wide screens', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.goto('/', { waitUntil: 'domcontentloaded' });
  await page.evaluate(() => document.fonts.ready);
  const film = await page.getByTestId('promo-film').boundingBox();
  const copy = await page.getByTestId('hero').locator('.hero-copy').boundingBox();
  expect(film && copy).toBeTruthy();
  expect(film!.width).toBeGreaterThan(copy!.width);
  expect(film!.width).toBeGreaterThanOrEqual(700);
  // Side by side, and the film starts above the fold.
  expect(film!.x).toBeGreaterThan(copy!.x + copy!.width - 1);
  expect(film!.y + film!.height).toBeLessThanOrEqual(900);
});
