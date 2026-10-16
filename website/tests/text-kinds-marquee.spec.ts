import { test, expect } from '@playwright/test';

// The text-kinds band under the hero: empty text fields glide past the
// recording pill and get their text once they have passed it. Every kind is
// announced once (the moving band is aria-hidden), it sits in the story
// order, it never causes horizontal overflow, and it stands still for
// reduced-motion users with every field filled.
for (const { path, first } of [
  { path: '/', first: 'Review-Kommentare' },
  { path: '/en/', first: 'Review comments' },
  { path: '/zh/', first: '代码评审意见' },
]) {
  test(`${path}: text-kinds band renders localized items once for assistive tech`, async ({ page }) => {
    await page.goto(path);
    const band = page.getByTestId('text-kinds-marquee');
    await expect(band).toHaveAttribute('role', 'region');
    await expect(band).toHaveAttribute('aria-label', /.+/);
    await expect(band.locator('ul li')).toHaveCount(10);
    await expect(band.locator('ul li').first()).toHaveText(first);
    await expect(band.locator('.tk-stage')).toHaveAttribute('aria-hidden', 'true');
  });
}

test('fields past the pill are filled, fields ahead of it wait empty', async ({ page }) => {
  await page.goto('/');
  const band = page.getByTestId('text-kinds-marquee');
  await band.scrollIntoViewIfNeeded();
  await expect(band).toHaveAttribute('data-js', '');
  const state = async () =>
    band.evaluate((el) => {
      const pill = el.querySelector('.tk-pill')!.getBoundingClientRect();
      const pillX = pill.left + pill.width / 2;
      return [...el.querySelectorAll<HTMLElement>('[data-tk-field]')].map((f) => {
        const r = f.getBoundingClientRect();
        return { left: r.left + r.width / 2 < pillX, filled: f.dataset.filled !== undefined, x: r.left };
      });
    });
  const before = await state();
  for (const f of before) expect(f.filled).toBe(f.left);
  // The row moves.
  await page.waitForTimeout(600);
  const after = await state();
  expect(after[0].x).toBeLessThan(before[0].x);
});

test('text-kinds band sits between the hero and the use-case cards', async ({ page }) => {
  await page.goto('/');
  const order = await page.evaluate(() => {
    const ids = ['#how-it-works', '[data-testid="text-kinds-marquee"]', '#use-cases'];
    return ids.map((s) => document.querySelector(s)!.getBoundingClientRect().top + window.scrollY);
  });
  expect(order[0]).toBeLessThan(order[1]);
  expect(order[1]).toBeLessThan(order[2]);
});

test('text-kinds band causes no horizontal overflow at 390px', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/');
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
  expect(overflow).toBeLessThanOrEqual(0);
});

test('text-kinds band stands still under reduced motion', async ({ page }) => {
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await page.goto('/');
  const band = page.getByTestId('text-kinds-marquee');
  await band.scrollIntoViewIfNeeded();
  await expect(band).not.toHaveAttribute('data-js', /.*/);
  const x0 = await band.locator('[data-tk-field]').first().evaluate((el) => el.getBoundingClientRect().left);
  await page.waitForTimeout(500);
  const x1 = await band.locator('[data-tk-field]').first().evaluate((el) => el.getBoundingClientRect().left);
  expect(x1).toBe(x0);
  await expect(band.locator('.tk-field__value').first()).toBeVisible();
});
