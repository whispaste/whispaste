import { test, expect } from '@playwright/test';

// The kinetic text-kinds band between the paste demo and the use-case cards:
// every item is announced once (the loop copy is aria-hidden), it sits in the
// story order, it never causes horizontal overflow, and it stands still for
// reduced-motion users.
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
    await expect(band.locator('ul:not([aria-hidden])')).toHaveCount(2);
    await expect(band.locator('ul[aria-hidden="true"]')).toHaveCount(2);
    await expect(band.locator('ul:not([aria-hidden]) li')).toHaveCount(10);
    await expect(band.locator('ul:not([aria-hidden]) li').first()).toHaveText(first);
  });
}

test('text-kinds band sits between the paste demo and the use-case cards', async ({ page }) => {
  await page.goto('/');
  const order = await page.evaluate(() => {
    const ids = ['#app-paste-demo', '[data-testid="text-kinds-marquee"]', '#use-cases'];
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
  const anim = await band.locator('.tk-row').first().evaluate((el) => getComputedStyle(el).animationName);
  expect(anim).toBe('none');
  await expect(band.locator('ul[aria-hidden="true"]').first()).toBeHidden();
});
