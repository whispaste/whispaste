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
  await expect(page.getByTestId('blog-article').getByRole('heading', { level: 1 })).toBeVisible();
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
