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

  test('teaser waits for the pause and for scrolling past the hero, is dismissed for good, panel never auto-opens', async ({ page }) => {
    await freezeClock(page);
    await page.goto('/en/');
    await expect(page.getByTestId('contact-badge')).toBeVisible();
    await expect(page.getByTestId('contact-teaser')).toBeHidden();
    // The pause is over, but the visitor is still on the hero: no teaser.
    await page.clock.runFor(7000);
    await expect(page.getByTestId('contact-teaser')).toBeHidden();
    await page.evaluate(() => {
      const hero = document.querySelector<HTMLElement>('[data-testid="hero"]')!;
      window.scrollTo({ top: hero.offsetTop + hero.offsetHeight + 100, behavior: 'instant' });
    });
    await expect(page.getByTestId('contact-teaser')).toBeVisible();
    await expect(page.getByTestId('contact-panel')).toBeHidden();

    // Dismissing the greeting keeps the badge: it stays until the panel was opened.
    await page.getByTestId('contact-teaser-dismiss').click();
    await expect(page.getByTestId('contact-teaser')).toBeHidden();
    await expect(page.getByTestId('contact-badge')).toBeVisible();

    await page.reload();
    await page.clock.runFor(7000);
    await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
    await expect(page.getByTestId('contact-teaser')).toBeHidden();
    await expect(page.getByTestId('contact-badge')).toBeVisible();

    await page.getByTestId('contact-launcher').click();
    await expect(page.getByTestId('contact-badge')).toBeHidden();
    await page.reload();
    await expect(page.getByTestId('contact-launcher')).toBeVisible();
    await expect(page.getByTestId('contact-badge')).toBeHidden();
  });

  test('a known question gets the answer with a link into the FAQ', async ({ page }) => {
    await page.goto('/en/');
    await page.getByTestId('contact-launcher').click();
    await page.getByTestId('contact-question').fill('Do I have to pay for it?');
    await page.keyboard.press('Enter');
    const answer = page.getByTestId('contact-answer');
    await expect(answer).toBeVisible();
    await expect(answer).toBeFocused();
    await expect(page.getByTestId('contact-answer-link')).toHaveAttribute('href', /#faq-free$/);
    await page.getByTestId('contact-answer-yes').click();
    await expect(page.getByTestId('contact-thanks')).toBeVisible();
    await page.getByTestId('contact-thanks-again').click();
    await expect(page.getByTestId('contact-question')).toBeFocused();
    await expect(page.getByTestId('contact-question')).toHaveValue('');
  });

  test('an ambiguous question offers at most three suggestions', async ({ page }) => {
    // Labelled `choose` question from src/data/faq-match-questions.ts.
    await page.goto('/en/');
    await page.getByTestId('contact-launcher').click();
    await page.getByTestId('contact-question').fill('Which model for my GPU?');
    await page.getByTestId('contact-ask-submit').click();
    await expect(page.getByTestId('contact-suggest-step')).toBeVisible();
    const suggestions = page.getByTestId('contact-suggest-step').locator('[data-testid^="contact-suggestion-"]');
    const count = await suggestions.count();
    expect(count).toBeGreaterThanOrEqual(2);
    expect(count).toBeLessThanOrEqual(3);
    await page.getByTestId('contact-suggestion-sysreq').click();
    await expect(page.getByTestId('contact-answer-link')).toHaveAttribute('href', /#faq-sysreq$/);

    // "No" leads to the email with the question prefilled.
    await page.getByTestId('contact-answer-no').click();
    await expect(page.getByTestId('contact-message')).toHaveValue('Which model for my GPU?');
  });

  test('an unknown question becomes an editable, prefilled email', async ({ page }) => {
    let body: Record<string, unknown> = {};
    await page.route(ENDPOINT, (route) => {
      body = route.request().postDataJSON() as Record<string, unknown>;
      return route.fulfill({ status: 202, contentType: 'application/json', body: '{"status":"accepted"}' });
    });
    await page.goto('/');
    await page.getByTestId('contact-launcher').click();
    await page.getByTestId('contact-question').fill('Mein Mikrofon wird nicht erkannt');
    await page.keyboard.press('Enter');
    await expect(page.getByTestId('contact-unknown')).toBeVisible();
    const message = page.getByTestId('contact-message');
    await expect(message).toBeFocused();
    await expect(message).toHaveValue('Mein Mikrofon wird nicht erkannt');
    await message.press('End');
    await message.pressSequentially(' (USB headset)');
    await page.getByTestId('contact-email').fill('visitor@example.org');
    await page.getByTestId('contact-submit').click();
    await expect(page.getByTestId('contact-sent')).toBeVisible();
    expect(body).toMatchObject({ kind: 'question', message: 'Mein Mikrofon wird nicht erkannt (USB headset)', lang: 'de' });
  });

  test('dismissed teaser does not come back after scrolling', async ({ page }) => {
    await freezeClock(page);
    await page.goto('/en/');
    await page.clock.runFor(7000);
    await page.evaluate(() => {
      const hero = document.querySelector<HTMLElement>('[data-testid="hero"]')!;
      window.scrollTo({ top: hero.offsetTop + hero.offsetHeight + 100, behavior: 'instant' });
    });
    await expect(page.getByTestId('contact-teaser')).toBeVisible();
    await page.getByTestId('contact-teaser-dismiss').click();
    await expect(page.getByTestId('contact-teaser')).toBeHidden();
    await page.evaluate(() => window.scrollTo(0, 0));
    await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
    await expect(page.getByTestId('contact-teaser')).toBeHidden();
  });

  test('no teaser over the hero on first load', async ({ page }) => {
    await freezeClock(page);
    await page.goto('/en/');
    await page.clock.runFor(30000);
    await expect(page.getByTestId('contact-teaser')).toBeHidden();
    await expect(page.getByTestId('contact-panel')).toBeHidden();
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

  test('FAQ open nudges the panel, but not with reduced motion', async ({ page }) => {
    await page.goto('/en/');
    const panel = page.getByTestId('contact-panel');
    // Record animation starts before clicking so a short animation cannot be missed.
    const started = () => panel.evaluate((el) => (el as HTMLElement & { started: string[] }).started);
    await panel.evaluate((el) => {
      const target = el as HTMLElement & { started: string[] };
      target.started = [];
      el.addEventListener('animationstart', (e) => target.started.push((e as AnimationEvent).animationName));
    });
    await page.getByTestId('faq-ask-open').click();
    await expect(panel).toBeVisible();
    await expect(panel).toHaveClass(/is-nudged/);

    await page.emulateMedia({ reducedMotion: 'reduce' });
    await page.getByTestId('contact-close').click();
    await panel.evaluate((el) => { (el as HTMLElement & { started: string[] }).started = []; });
    await page.getByTestId('faq-ask-open').click();
    await expect(panel).toBeVisible();
    await page.waitForTimeout(300);
    expect(await started()).toEqual([]);
    expect(await panel.evaluate((el) => el.getAnimations().length)).toBe(0);
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

  test('no teaser on mobile before scrolling past the hero', async ({ page }) => {
    await freezeClock(page);
    await page.goto('/en/');
    await page.clock.runFor(7000);
    await expect(page.getByTestId('contact-teaser')).toBeHidden();
  });

  test('greeting and badge work on phones too and survive a reload', async ({ page }) => {
    await freezeClock(page);
    await page.goto('/en/');
    await expect(page.getByTestId('contact-badge')).toBeVisible();
    await page.clock.runFor(7000);
    await page.evaluate(() => {
      const hero = document.querySelector<HTMLElement>('[data-testid="hero"]')!;
      window.scrollTo({ top: hero.offsetTop + hero.offsetHeight + 100, behavior: 'instant' });
    });
    await expect(page.getByTestId('contact-teaser')).toBeVisible();

    // Shown once is enough, also without dismissing it.
    await page.reload();
    await page.clock.runFor(7000);
    await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
    await expect(page.getByTestId('contact-teaser')).toBeHidden();
    await expect(page.getByTestId('contact-badge')).toBeVisible();
  });
});

test.describe('without JavaScript', () => {
  test.use({ javaScriptEnabled: false });

  test('address and mailto link are visible, the launcher is not', async ({ page }) => {
    await page.goto('/en/');
    const nojs = page.getByTestId('contact-nojs');
    await expect(nojs).toBeVisible();
    await expect(nojs).toContainText('kontakt@whispaste.de');
    await expect(nojs.locator('a[href^="mailto:kontakt@whispaste.de"]')).toBeVisible();
    await expect(page.getByTestId('contact-launcher')).toBeHidden();
  });
});
