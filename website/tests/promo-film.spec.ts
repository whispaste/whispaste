import { expect, test } from '@playwright/test';

// Promo film as the hero visual: a silent, looping brand film that must never
// autoplay for reduced-motion users and must stay pausable (WCAG 2.2.2 —
// moving content longer than 5 s needs a pause control).
for (const { path, lang } of [
  { path: '/', lang: 'de' },
  { path: '/en/', lang: 'en' },
]) {
  test.describe(`PromoFilm (${lang})`, () => {
    test('is the hero visual and serves the locale-matching cut', async ({ page }) => {
      await page.goto(path);
      const hero = page.getByTestId('hero');
      await expect(hero.getByTestId('promo-film')).toHaveCount(1);
      // No separate film section any more: the hero hands off directly to
      // the step-by-step demo. Astro may emit a <script> in between.
      const nextId = await hero.evaluate((el) => {
        let next = el.nextElementSibling;
        while (next && next.tagName !== 'SECTION') next = next.nextElementSibling;
        return next?.id ?? '';
      });
      expect(nextId).toBe('app-paste-demo');

      // The poster is the LCP element and is preloaded from the head.
      await expect(
        page.locator(`head link[rel="preload"][as="image"][href="/videos/whispaste-promo-16x9-${lang}-poster.jpg"]`),
      ).toHaveCount(1);

      const video = page.getByTestId('promo-film-video');
      await expect(video).toHaveAttribute('poster', `/videos/whispaste-promo-16x9-${lang}-poster.jpg`);
      await expect(video).toHaveJSProperty('muted', true);
      const sources = await video.locator('source').evaluateAll((els) =>
        els.map((el) => [el.getAttribute('src'), el.getAttribute('type')]),
      );
      expect(sources).toEqual([
        [`/videos/whispaste-promo-16x9-${lang}.webm`, 'video/webm'],
        [`/videos/whispaste-promo-16x9-${lang}.mp4`, 'video/mp4'],
      ]);
      await expect(video).toHaveAttribute('aria-label', /.+/);
    });

    test('pause toggle stops and resumes playback', async ({ page }) => {
      await page.goto(path);
      await page.getByTestId('promo-film').scrollIntoViewIfNeeded();
      const video = page.getByTestId('promo-film-video');
      const toggle = page.getByTestId('promo-film-toggle');
      await expect.poll(() => video.evaluate((v: HTMLVideoElement) => v.paused)).toBe(false);
      await expect(toggle).toHaveAttribute('aria-pressed', 'false');
      await toggle.click();
      await expect.poll(() => video.evaluate((v: HTMLVideoElement) => v.paused)).toBe(true);
      await expect(toggle).toHaveAttribute('aria-pressed', 'true');
      await toggle.click();
      await expect.poll(() => video.evaluate((v: HTMLVideoElement) => v.paused)).toBe(false);
    });
  });
}

test.describe('PromoFilm with reduced motion', () => {
  test('does not autoplay and offers play instead', async ({ page }) => {
    await page.emulateMedia({ reducedMotion: 'reduce' });
    await page.goto('/');
    await page.getByTestId('promo-film').scrollIntoViewIfNeeded();
    const video = page.getByTestId('promo-film-video');
    await page.waitForTimeout(500);
    expect(await video.evaluate((v: HTMLVideoElement) => v.paused)).toBe(true);
    await expect(page.getByTestId('promo-film-toggle')).toHaveAttribute('aria-pressed', 'true');
  });
});

test('hero with film fits a 390 px viewport without horizontal scroll', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/');
  const box = await page.getByTestId('promo-film-video').boundingBox();
  expect(box).not.toBeNull();
  expect(box!.x).toBeGreaterThanOrEqual(0);
  expect(box!.x + box!.width).toBeLessThanOrEqual(390);
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth);
  expect(overflow).toBe(false);
  // Stacked layout on phones: the headline comes first, the film below it.
  const h1 = await page.getByTestId('hero').locator('h1').boundingBox();
  expect(h1).not.toBeNull();
  expect(box!.y).toBeGreaterThan(h1!.y);
});
