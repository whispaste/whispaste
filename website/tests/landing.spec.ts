import { expect, test } from '@playwright/test';

test.beforeEach(async ({ page }) => {
  await page.addInitScript(() => {
    window.localStorage.clear();
  });
});

test('hero CTA contains platform download button(s)', async ({ page }) => {
  await page.goto('/');

  // At least one download button must be visible (platform-adaptive: one or both shown)
  const storeBtn = page.getByTestId('store-button').first();
  const appleBtn = page.getByTestId('apple-button').first();
  const storeVisible = await storeBtn.isVisible();
  const appleVisible = await appleBtn.isVisible();
  expect(storeVisible || appleVisible).toBe(true);
});

test('language toggle switches the landing page from EN to DE', async ({ page }) => {
  await page.goto('/');

  const heroHeading = page.locator('section h1').first();
  await expect(heroHeading).toContainText('Press. Speak.');
  await page.getByTestId('lang-toggle').click();
  await expect(heroHeading).toContainText('Drücken. Sprechen.');
});

test('FAQ section is visible and has accordion items', async ({ page }) => {
  await page.goto('/');

  const faq = page.locator('#faq');
  await faq.scrollIntoViewIfNeeded();
  await expect(faq).toBeVisible();
  await expect(faq.locator('details')).toHaveCount(9);
});

test('legal pages load without 404s', async ({ page }) => {
  await page.goto('/datenschutz/');
  await expect(page.locator('#pageTitle')).toBeVisible();

  await page.goto('/impressum/');
  await expect(page.locator('#pageTitle')).toBeVisible();
});

test('download page has Store and GitHub sections', async ({ page }) => {
  await page.goto('/download/');
  await expect(page.locator('main h1').first()).toContainText('Download');
  await expect(page.locator('main h2').first()).toContainText('Microsoft Store');
  // GitHub free download section — Windows button has data-testid="github-windows-button"
  await expect(page.getByTestId('github-windows-button')).toBeVisible();
});

test('hero recording pill matches the in-app recording state in dark and light theme', async ({ page }) => {
  await page.goto('/');
  await page.evaluate(() => {
    document.documentElement.classList.remove('light');
  });
  await page.locator('.carousel-dot').nth(1).click();

  const pill = page.locator('.overlay-pill');
  await expect(pill).toBeVisible();
  await expect(page.locator('.overlay-badge-ai')).toHaveCount(0);
  await expect(page.locator('.overlay-ai-gap')).toHaveCount(1);
  await expect(page.locator('.overlay-wave-bar')).toHaveCount(30);
  await expect(page.locator('#overlay-progress-fill')).toHaveCount(1);
  await expect(page.locator('.overlay-btn-stop svg')).toHaveAttribute('fill', 'none');
  await expect(page.locator('.overlay-btn-stop svg')).toHaveAttribute('stroke', 'white');

  const darkMetrics = await page.evaluate(() => {
    const pillEl = document.querySelector('.overlay-pill') as HTMLElement;
    const cancelEl = document.querySelector('.overlay-btn-cancel') as HTMLElement;
    const gapEl = document.querySelector('.overlay-ai-gap') as HTMLElement;
    const stopEl = document.querySelector('.overlay-btn-stop') as HTMLElement;
    const waveformEl = document.querySelector('.overlay-waveform') as HTMLElement;
    const pillStyle = getComputedStyle(pillEl);

    return {
      background: pillStyle.backgroundColor,
      backdropFilter: pillStyle.backdropFilter || (pillStyle as CSSStyleDeclaration & { webkitBackdropFilter?: string }).webkitBackdropFilter || '',
      cancelMarginRight: getComputedStyle(cancelEl).marginRight,
      gapWidth: getComputedStyle(gapEl).width,
      stopMarginLeft: getComputedStyle(stopEl).marginLeft,
      waveformAlignItems: getComputedStyle(waveformEl).alignItems,
    };
  });

  expect(darkMetrics.background).toBe('rgba(20, 25, 38, 0.8)');
  expect(darkMetrics.backdropFilter).toContain('blur(12px)');
  expect(darkMetrics.cancelMarginRight).toBe('12px');
  expect(darkMetrics.gapWidth).toBe('8px');
  expect(darkMetrics.stopMarginLeft).toBe('12px');
  expect(darkMetrics.waveformAlignItems).toBe('flex-end');

  await expect
    .poll(async () => {
      return page.locator('#overlay-progress-fill').evaluate((el) => (el as HTMLElement).style.width);
    })
    .not.toBe('0%');

  await page.evaluate(() => {
    document.documentElement.classList.add('light');
  });

  await expect
    .poll(async () => {
      return page.locator('.overlay-pill').evaluate((el) => getComputedStyle(el as HTMLElement).backgroundColor);
    })
    .toBe('rgba(240, 243, 247, 0.8)');
});
