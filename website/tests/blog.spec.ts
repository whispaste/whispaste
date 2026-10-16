import { expect, test } from '@playwright/test';

// The blog is linked from the top nav and the footer, and lists its posts.
for (const [path, blogHref] of [['/', '/blog/'], ['/en/', '/en/blog/'], ['/es/', '/en/blog/']] as const) {
  test(`${path}: nav and footer link to the blog`, async ({ page }) => {
    await page.goto(path);
    await expect(page.getByTestId('nav-link-blog')).toHaveAttribute('href', blogHref);
    await expect(page.getByTestId('footer-link-blog')).toHaveAttribute('href', blogHref);
  });
}

test('blog index lists a post that opens', async ({ page }) => {
  await page.goto('/blog/');
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('Blog');
  await page.getByTestId('blog-list').getByRole('link').first().click();
  await expect(page.getByTestId('blog-hero').getByRole('heading', { level: 1 })).toBeVisible();
  await expect(page.getByTestId('blog-article')).toHaveAttribute('aria-labelledby', 'post-title');
});

// Same frame as every other subpage: head on the dark stage, content in
// the light page sheet.
for (const path of ['/blog/', '/blog/vom-hotkey-zum-text-im-aktiven-fenster/']) {
  test(`${path}: head on the stage, content in the light sheet`, async ({ page }) => {
    await page.goto(path);
    await expect(page.getByTestId('blog-hero').getByRole('heading', { level: 1 })).toBeVisible();
    const sheet = page.getByTestId('page-sheet');
    await expect(sheet).toHaveAttribute('data-surface', 'light');
    await expect(sheet.getByTestId(path === '/blog/' ? 'blog-list' : 'blog-article')).toBeVisible();
  });
}

test('blog index leads with the newest post and uses the full landing footer', async ({ page }) => {
  await page.goto('/blog/');
  const cards = page.getByTestId('blog-list').getByRole('link');
  await expect(cards.first()).toContainText('Neuester Beitrag');
  expect(await cards.count()).toBeGreaterThan(1);
  await expect(page.getByTestId('footer-resources')).toBeVisible();
  await expect(page.getByTestId('footer-link-impressum')).toBeVisible();
});

test('blog post has a table of contents, a download CTA and more posts', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.goto('/blog/lokal-diktieren-ohne-nvidia-pflicht/');
  const toc = page.getByTestId('blog-toc');
  await expect(toc).toBeVisible();
  const firstTarget = await toc.getByRole('link').first().getAttribute('href');
  await expect(page.locator(`[data-testid="blog-article"] ${firstTarget}`)).toHaveCount(1);
  await expect(page.getByTestId('blog-cta-download')).toHaveAttribute('href', '/download/');
  await expect(page.getByTestId('blog-more').getByRole('link')).not.toHaveCount(0);
  await expect(page.getByTestId('blog-more')).not.toContainText('Brauche ich eine NVIDIA');
});

test('blog pages cause no horizontal overflow at 390px', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  for (const path of ['/blog/', '/en/blog/', '/blog/vom-hotkey-zum-text-im-aktiven-fenster/']) {
    await page.goto(path);
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
    expect(overflow, path).toBeLessThanOrEqual(0);
  }
});

test('English blog index renders English posts', async ({ page }) => {
  await page.goto('/en/blog/');
  await expect(page.getByTestId('blog-list')).toContainText(/model size/i);
});

for (const [feed, post] of [['/blog/feed.xml', 'https://whispaste.de/blog/'], ['/en/blog/feed.xml', 'https://whispaste.de/en/blog/']] as const) {
  test(`${feed}: RSS feed lists posts and is advertised on the index`, async ({ page, request }) => {
    const res = await request.get(feed);
    expect(res.status()).toBe(200);
    const xml = await res.text();
    expect(xml).toContain('<rss version="2.0"');
    expect(xml).toContain(`<link>${post}`);
    await page.goto(feed.replace('feed.xml', ''));
    await expect(page.locator(`link[rel="alternate"][type="application/rss+xml"][href="${feed}"]`)).toHaveCount(1);
  });
}

test('blog post offers a Google Translate hand-off that sends nothing until submitted', async ({ page }) => {
  await page.goto('/blog/welche-modellgroesse-fuer-lokales-diktieren/');
  const form = page.getByTestId('blog-translate');
  await expect(form).toHaveAttribute('action', 'https://translate.google.com/translate');
  await expect(form.locator('input[name="u"]')).toHaveValue('https://whispaste.de/blog/welche-modellgroesse-fuer-lokales-diktieren/');
  await expect(form.locator('input[name="sl"]')).toHaveValue('de');
  await expect(page.getByTestId('blog-translate-select')).toHaveValue('es');
});
