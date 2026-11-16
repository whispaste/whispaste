import { expect, test } from '@playwright/test';

/**
 * What "Sign up" on the newsletter page triggers: nothing without the
 * consent tick, one request to the API with it, and the confirmation step
 * after a 202. Elements are found by data-testid; wording is judged by eye.
 */

const ENDPOINT = 'https://api.whispaste.de/v1/newsletter/subscribe';

test.describe('newsletter page', () => {
  test('without consent nothing is sent', async ({ page }) => {
    let calls = 0;
    await page.route(ENDPOINT, (route) => {
      calls += 1;
      return route.fulfill({ status: 202, contentType: 'application/json', body: '{"status":"accepted"}' });
    });
    await page.goto('/en/newsletter/');
    await page.getByTestId('newsletter-email').fill('anna@example.org');
    await page.getByTestId('newsletter-submit').click();
    await expect(page.getByTestId('newsletter-status')).not.toBeEmpty();
    expect(calls).toBe(0);
  });

  test('with consent one sign-up goes out and the page says to confirm', async ({ page }) => {
    let body: Record<string, unknown> | null = null;
    await page.route(ENDPOINT, (route) => {
      body = route.request().postDataJSON() as Record<string, unknown>;
      return route.fulfill({ status: 202, contentType: 'application/json', body: '{"status":"accepted"}' });
    });
    await page.goto('/fr/newsletter/');
    await page.getByTestId('newsletter-email').fill('anna@example.org');
    await page.getByTestId('newsletter-consent').check();
    await page.getByTestId('newsletter-submit').click();
    await expect(page.getByTestId('newsletter-sent')).toBeVisible();
    expect(body).toMatchObject({
      email: 'anna@example.org',
      source: 'web',
      consent: 'newsletter-2026-10-31',
      locale: 'fr',
      website: '',
    });
    expect((body as unknown as { elapsed: number }).elapsed).toBeGreaterThanOrEqual(2500);
  });

  test('a refusal keeps the form and the address', async ({ page }) => {
    await page.route(ENDPOINT, (route) =>
      route.fulfill({ status: 429, contentType: 'application/problem+json', body: '{"status":429}' }),
    );
    await page.goto('/newsletter/');
    await page.getByTestId('newsletter-email').fill('anna@example.org');
    await page.getByTestId('newsletter-consent').check();
    await page.getByTestId('newsletter-submit').click();
    await expect(page.getByTestId('newsletter-status')).not.toBeEmpty();
    await expect(page.getByTestId('newsletter-email')).toHaveValue('anna@example.org');
    await expect(page.getByTestId('newsletter-sent')).toBeHidden();
  });

  test('the footer links the page', async ({ page }) => {
    await page.goto('/en/');
    await expect(page.getByTestId('footer-link-newsletter')).toHaveAttribute('href', '/en/newsletter/');
  });
});
