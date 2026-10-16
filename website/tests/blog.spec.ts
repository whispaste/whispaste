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
  await expect(page.getByTestId('blog-list').getByRole('link').first()).toContainText(/model size/i);
});
