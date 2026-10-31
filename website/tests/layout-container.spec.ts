import { expect, test } from '@playwright/test';

// One shared frame (global.css): the floating nav pill uses the full frame
// (`.wp-frame`) and is always the widest element; section content
// (`.wp-container`) is inset symmetrically by --nav-overhang so the pill's
// rounded ends overhang it. Nothing may scroll sideways.
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

      // The hero frame is centred under the nav pill and inset on both sides
      // by the same small overhang (8-16 px), never flush and never wider.
      const hero = await page.getByTestId('hero').locator(':scope > .wp-container').boundingBox();
      expect(hero).not.toBeNull();
      const insetLeft = hero!.x - nav!.x;
      const insetRight = nav!.x + nav!.width - (hero!.x + hero!.width);
      expect(insetLeft).toBeGreaterThanOrEqual(7);
      expect(insetLeft).toBeLessThanOrEqual(17);
      expect(Math.abs(insetLeft - insetRight)).toBeLessThanOrEqual(1);

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

test('hero stage spans the container, the example sits in the photo\'s calm right half', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.goto('/', { waitUntil: 'domcontentloaded' });
  await page.evaluate(() => document.fonts.ready);
  const stage = await page.getByTestId('hero-stage').boundingBox();
  const example = await page.getByTestId('hero-example').boundingBox();
  const title = await page.getByTestId('hero').locator('h1').boundingBox();
  expect(stage && example && title).toBeTruthy();
  // The stage is a wide panel, not a narrow column (anti-slop: no narrow
  // containers on wide screens). The speaker owns the left half of the
  // photo, the example card the right half.
  expect(stage!.width).toBeGreaterThanOrEqual(1200);
  expect(example!.width).toBeGreaterThanOrEqual(520);
  expect(example!.x).toBeGreaterThan(stage!.x + stage!.width / 2);
  expect(example!.x + example!.width).toBeLessThanOrEqual(stage!.x + stage!.width);
  // Story order: headline first, the product below it.
  expect(example!.y).toBeGreaterThan(title!.y + title!.height);
});

test('hero photo carries the AI label and the footer explains it', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.goto('/');
  await expect(page.getByTestId('hero-ai-badge')).toHaveText('KI-generiert');
  await expect(page.getByTestId('footer-ai-note')).toContainText('KI-generiert');
  await page.goto('/en/');
  await expect(page.getByTestId('hero-ai-badge')).toHaveText('AI-generated');
});
