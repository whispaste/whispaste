import { expect, test } from '@playwright/test';

// Open source: right below the use cases, four numbered ways to take part
// with their links, a motion loop and a nav entry pointing here.
const WAYS = {
  issue: 'https://github.com/whispaste/whispaste/issues/new/choose',
  pr: 'https://github.com/whispaste/whispaste/blob/main/CONTRIBUTING.md',
  ideas: 'https://app.votepit.com/silvio-und-maik/whispaste',
  translate: 'https://github.com/whispaste/whispaste/blob/main/CONTRIBUTING_TRANSLATIONS.md',
};

test('links every way in', async ({ page }) => {
  await page.goto('/en/');

  const section = page.getByTestId('open-source');
  await expect(page.getByTestId('open-source-github')).toHaveAttribute('href', 'https://github.com/whispaste/whispaste');
  for (const [key, href] of Object.entries(WAYS)) {
    await expect(page.getByTestId(`open-source-link-${key}`)).toHaveAttribute('href', href);
  }
  await expect(section.locator('.os-way')).toHaveCount(4);
});

test('the nav links to the section in every place it shows', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.goto('/');
  await page.getByTestId('nav-link-community').click();
  await expect(page).toHaveURL(/#open-source$/);
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
