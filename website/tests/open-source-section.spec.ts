import { expect, test } from '@playwright/test';

// Open source: right below the use cases, four numbered ways to take part
// with their links, a motion loop and a nav entry pointing here.
const WAYS = {
  issue: 'https://github.com/whispaste/whispaste/issues/new/choose',
  pr: 'https://github.com/whispaste/whispaste/blob/main/CONTRIBUTING.md',
  ideas: 'https://app.votepit.com/silvio-und-maik/whispaste',
  translate: 'https://github.com/whispaste/whispaste/blob/main/CONTRIBUTING_TRANSLATIONS.md',
};

test('sits right after the use cases and links every way in', async ({ page }) => {
  await page.goto('/en/');
  const order = await page.evaluate(() =>
    [...document.querySelectorAll('main > section[id]')].map((s) => s.id),
  );
  expect(order[order.indexOf('use-cases') + 1]).toBe('open-source');

  const section = page.getByTestId('open-source');
  await expect(section.getByRole('heading', { level: 2 })).toHaveText('Make WhisPaste better with us');
  await expect(page.getByTestId('open-source-github')).toHaveAttribute('href', 'https://github.com/whispaste/whispaste');
  for (const [key, href] of Object.entries(WAYS)) {
    await expect(page.getByTestId(`open-source-link-${key}`)).toHaveAttribute('href', href);
  }
  await expect(section.locator('.os-way')).toHaveCount(4);
});

test('shares one light sheet with the use cases, a thin rule on the seam', async ({ page }) => {
  await page.goto('/');
  const radii = await page.evaluate(() => {
    const css = (id: string) => getComputedStyle(document.getElementById(id)!);
    const rule = getComputedStyle(document.querySelector('#open-source > .wp-container')!, '::before');
    return {
      above: css('use-cases').borderBottomLeftRadius,
      below: css('open-source').borderTopRightRadius,
      ruleHeight: rule.height,
      gap: document.getElementById('open-source')!.getBoundingClientRect().top - document.getElementById('use-cases')!.getBoundingClientRect().bottom,
    };
  });
  expect(radii).toEqual({ above: '0px', below: '0px', ruleHeight: '1px', gap: 0 });
});

test('the nav links to the section in every place it shows', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.goto('/');
  await expect(page.getByTestId('nav-link-community')).toHaveText('Open Source');
  await page.getByTestId('nav-link-community').click();
  await expect(page).toHaveURL(/#open-source$/);
  await expect(page.getByTestId('open-source')).toBeInViewport();
});

test('loop plays on screen, poster only with reduced motion', async ({ browser }) => {
  for (const reducedMotion of ['reduce', 'no-preference'] as const) {
    const context = await browser.newContext({ reducedMotion });
    const page = await context.newPage();
    await page.goto('/');
    const video = page.getByTestId('open-source-video');
    await expect(video).toHaveAttribute('poster', '/motion/community.webp');
    // The playing loop never counts as "stable", so scroll without waiting.
    await video.evaluate((v) => v.scrollIntoView({ block: 'center' }));
    if (reducedMotion === 'reduce') {
      await page.waitForTimeout(500);
      expect(await video.evaluate((v: HTMLVideoElement) => v.paused && !v.currentSrc)).toBe(true);
    } else {
      await expect.poll(() => video.evaluate((v: HTMLVideoElement) => !v.paused)).toBe(true);
      expect(await video.evaluate((v: HTMLVideoElement) => v.currentSrc)).toMatch(/community\.webm$/);
    }
    await context.close();
  }
});

test('motion files are served', async ({ request }) => {
  for (const ext of ['webm', 'mov', 'webp']) {
    expect((await request.get(`/motion/community.${ext}`)).ok()).toBe(true);
  }
});

test('fits without sideways scroll at 390px', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/');
  await page.getByTestId('open-source').scrollIntoViewIfNeeded();
  const overflow = await page.evaluate(
    () => document.documentElement.scrollWidth - document.documentElement.clientWidth,
  );
  expect(overflow).toBeLessThanOrEqual(0);
});
