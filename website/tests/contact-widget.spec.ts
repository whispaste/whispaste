import { expect, test, type Page } from '@playwright/test';

// The contact widget never opens by itself, keeps the visitor's data on the
// page until "Send", and stays out of the way of the mobile CTA.

const ENDPOINT = '**/v1/contact';

// install() lets fake time run at real speed; pause it so the 6 s teaser
// timer only fires when a test advances the clock (no flake on slow runners).
async function freezeClock(page: Page) {
  const start = new Date('2026-10-16T10:00:00Z');
  await page.clock.install({ time: start });
  await page.clock.pauseAt(new Date(start.getTime() + 1000));
}

async function openForm(page: Page, kind: string) {
  await page.getByTestId('contact-launcher').click();
  await expect(page.getByTestId('contact-panel')).toBeVisible();
  await page.getByTestId(`contact-kind-${kind}`).click();
  await expect(page.getByTestId('contact-form')).toBeVisible();
}

test.describe('desktop', () => {
  test.use({ viewport: { width: 1440, height: 900 } });

  test('teaser appears later, is dismissed for good, panel never auto-opens', async ({ page }) => {
    await freezeClock(page);
    await page.goto('/en/');
    await expect(page.getByTestId('contact-badge')).toBeVisible();
    await expect(page.getByTestId('contact-teaser')).toBeHidden();
    await page.clock.runFor(7000);
    await expect(page.getByTestId('contact-teaser')).toBeVisible();
    await expect(page.getByTestId('contact-panel')).toBeHidden();

    await page.getByTestId('contact-teaser-dismiss').click();
    await expect(page.getByTestId('contact-teaser')).toBeHidden();
    await expect(page.getByTestId('contact-badge')).toBeHidden();

    await page.reload();
    await page.clock.runFor(7000);
    await expect(page.getByTestId('contact-teaser')).toBeHidden();
    await expect(page.getByTestId('contact-badge')).toBeHidden();
  });

  test('opens and closes via launcher, close button and Escape', async ({ page }) => {
    await page.goto('/en/');
    const launcher = page.getByTestId('contact-launcher');
    const panel = page.getByTestId('contact-panel');
    await launcher.click();
    await expect(panel).toBeVisible();
    await expect(launcher).toHaveAttribute('aria-expanded', 'true');
    await page.getByTestId('contact-close').click();
    await expect(panel).toBeHidden();
    await launcher.click();
    await page.keyboard.press('Escape');
    await expect(panel).toBeHidden();
    await expect(launcher).toHaveAttribute('aria-expanded', 'false');
  });

  test('panel wiggles after opening from the FAQ, not with reduced motion', async ({ page }) => {
    await page.goto('/en/');
    const panel = page.getByTestId('contact-panel');
    const names = () =>
      panel.evaluate((el) => el.getAnimations().map((a) => (a as CSSAnimation).animationName));
    await page.getByTestId('faq-ask-open').click();
    await expect(panel).toBeVisible();
    await expect(panel).toHaveClass(/is-nudged/);
    await expect.poll(names).toContain('cw-nudge');

    await page.emulateMedia({ reducedMotion: 'reduce' });
    await page.getByTestId('contact-close').click();
    await page.getByTestId('faq-ask-open').click();
    await expect(panel).toBeVisible();
    expect(await names()).toEqual([]);
  });

  test('ideas go to the public board, problems get the FAQ hint', async ({ page }) => {
    await page.goto('/en/');
    await page.getByTestId('contact-launcher').click();
    await page.getByTestId('contact-kind-idea').click();
    const board = page.getByTestId('contact-idea-board');
    await expect(board).toHaveAttribute('href', 'https://app.votepit.com/silvio-und-maik/whispaste');
    await expect(board).toHaveAttribute('rel', /noopener/);
    await page.getByTestId('contact-idea-back').click();

    await page.getByTestId('contact-kind-problem').click();
    await expect(page.getByTestId('contact-faq-link')).toHaveAttribute('href', /#faq$/);
  });

  test('nothing is sent until the input is valid', async ({ page }) => {
    let calls = 0;
    await page.route(ENDPOINT, (route) => {
      calls++;
      return route.fulfill({ status: 202, contentType: 'application/json', body: '{"status":"accepted"}' });
    });
    await page.goto('/en/');
    await openForm(page, 'question');
    await page.getByTestId('contact-message').fill('short');
    await page.getByTestId('contact-email').fill('not-an-address');
    await page.getByTestId('contact-submit').click();
    await expect(page.getByTestId('contact-status')).not.toHaveText('');
    await expect(page.getByTestId('contact-message')).toHaveAttribute('aria-invalid', 'true');
    expect(calls).toBe(0);
  });

  test('sends exactly the documented fields and confirms', async ({ page }) => {
    let body: Record<string, unknown> = {};
    await page.route(ENDPOINT, (route) => {
      body = route.request().postDataJSON() as Record<string, unknown>;
      return route.fulfill({ status: 202, contentType: 'application/json', body: '{"status":"accepted"}' });
    });
    await page.goto('/en/');
    await openForm(page, 'question');
    await page.getByTestId('contact-message').fill('Does WhisPaste work offline on Linux?');
    await page.getByTestId('contact-email').fill('visitor@example.org');
    await page.getByTestId('contact-submit').click();
    await expect(page.getByTestId('contact-sent')).toBeVisible();
    expect(Object.keys(body).sort()).toEqual(['elapsed', 'email', 'kind', 'lang', 'message', 'page', 'website']);
    expect(body).toMatchObject({ kind: 'question', email: 'visitor@example.org', lang: 'en', page: '/en/', website: '' });
  });

  test('rate limit answer is shown and the form stays usable', async ({ page }) => {
    await page.route(ENDPOINT, (route) =>
      route.fulfill({ status: 429, headers: { 'Retry-After': '600' }, contentType: 'application/problem+json', body: '{"title":"Too many requests","status":429}' }),
    );
    await page.goto('/en/');
    await openForm(page, 'other');
    await page.getByTestId('contact-message').fill('Hello there, a general note.');
    await page.getByTestId('contact-email').fill('visitor@example.org');
    await page.getByTestId('contact-submit').click();
    await expect(page.getByTestId('contact-status')).not.toHaveText('');
    await expect(page.getByTestId('contact-submit')).toBeEnabled();
    await expect(page.getByTestId('contact-sent')).toBeHidden();
  });
});

test.describe('mobile 390', () => {
  test.use({ viewport: { width: 390, height: 844 } });

  test('no teaser, no horizontal overflow, launcher clears the mobile CTA', async ({ page }) => {
    await freezeClock(page);
    await page.goto('/en/');
    await page.clock.runFor(7000);
    await expect(page.getByTestId('contact-teaser')).toBeHidden();

    await page.locator('#features').scrollIntoViewIfNeeded();
    await expect(page.getByTestId('mobile-cta')).toHaveClass(/visible/);
    // The launcher lifts with a transition once the bar shows; poll until it settles.
    await expect
      .poll(async () => {
        const launcher = await page.getByTestId('contact-launcher').boundingBox();
        const bar = await page.getByTestId('mobile-cta').boundingBox();
        return bar!.y - (launcher!.y + launcher!.height);
      })
      .toBeGreaterThanOrEqual(0);

    await page.getByTestId('contact-launcher').click();
    const panel = await page.getByTestId('contact-panel').boundingBox();
    expect(panel!.x).toBeGreaterThanOrEqual(0);
    expect(panel!.x + panel!.width).toBeLessThanOrEqual(390);
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
    expect(overflow).toBe(0);
  });
});
