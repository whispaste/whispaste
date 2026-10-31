import { expect, test } from '@playwright/test';

// Privacy shows two labelled audio paths (local default, optional cloud), a
// telemetry line and a link to the explainer page.
test('privacy section shows both audio paths and the details link', async ({ page }) => {
  await page.goto('/en/');
  const section = page.getByTestId('privacy');
  await section.scrollIntoViewIfNeeded();
  await expect(page.getByTestId('privacy-path-local')).toContainText('Default');
  await expect(page.getByTestId('privacy-path-local').locator('ol li')).toHaveCount(3);
  await expect(page.getByTestId('privacy-path-cloud')).toContainText('Only if you choose it');
  await expect(page.getByTestId('privacy-details')).toHaveAttribute('href', '/en/privacy-speech-recognition/');
});

// Each path has a transparent, text-free motion loop (VP9 WebM, HEVC .mov for
// WebKit, poster as the still) that assistive tech skips; the numbered list
// carries the words.
for (const key of ['local', 'cloud'] as const) {
  test(`${key} path shows its motion loop with poster and source files`, async ({ page, request }) => {
    await page.goto('/');
    const video = page.getByTestId(`privacy-video-${key}`);
    await expect(video).toHaveAttribute('poster', `/motion/privacy-${key}.webp`);
    await expect(video).toHaveAttribute('data-motion-loop', `/motion/privacy-${key}`);
    await expect(page.getByTestId(`privacy-path-${key}`).locator('figure')).toHaveAttribute('aria-hidden', 'true');
    for (const file of [`privacy-${key}.webp`, `privacy-${key}.webm`, `privacy-${key}.mov`]) {
      expect((await request.get(`/motion/${file}`)).ok()).toBe(true);
    }
  });
}

test('loops play on screen, but not with reduced motion', async ({ browser }) => {
  for (const reducedMotion of ['no-preference', 'reduce'] as const) {
    const page = await browser.newPage({ reducedMotion });
    await page.goto('/');
    await page.getByTestId('privacy-video-local').scrollIntoViewIfNeeded();
    const paused = () => page.getByTestId('privacy-video-local').evaluate((v: HTMLVideoElement) => v.paused);
    if (reducedMotion === 'reduce') {
      await page.waitForTimeout(800);
      expect(await paused()).toBe(true);
    } else {
      await expect.poll(paused).toBe(false);
      // Chromium gets the VP9 file (alpha); WebKit would get the HEVC .mov.
      expect(await page.getByTestId('privacy-video-local').evaluate((v: HTMLVideoElement) => v.currentSrc)).toMatch(/privacy-local\.webm$/);
    }
    await page.close();
  }
});

test('privacy routes fit without sideways scroll at 390px', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/');
  await page.getByTestId('privacy').scrollIntoViewIfNeeded();
  const overflow = await page.evaluate(
    () => document.documentElement.scrollWidth - document.documentElement.clientWidth,
  );
  expect(overflow).toBeLessThanOrEqual(0);
});
