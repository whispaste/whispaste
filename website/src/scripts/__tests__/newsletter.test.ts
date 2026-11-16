import { describe, expect, it, vi } from 'vitest';
import {
  NEWSLETTER_CONSENT_VERSION,
  NEWSLETTER_MIN_FILL_IN_MS,
  looksLikeNewsletterEmail,
  newsletterElapsedMs,
  newsletterOutcome,
  newsletterRequestBody,
  subscribeToNewsletter,
} from '../newsletter';

describe('newsletter request', () => {
  it('carries source web, the consent version and the honeypot as typed', () => {
    const body = JSON.parse(
      newsletterRequestBody({ email: ' anna@example.org ', locale: 'fr', elapsedMs: 4100, honeypot: '' }),
    );
    expect(body).toEqual({
      email: 'anna@example.org',
      source: 'web',
      consent: NEWSLETTER_CONSENT_VERSION,
      locale: 'fr',
      website: '',
      elapsed: 4100,
    });
  });

  it('a fast send is lifted to the server bar, a slow one kept', () => {
    expect(newsletterElapsedMs(1000, 1800)).toBe(NEWSLETTER_MIN_FILL_IN_MS);
    expect(newsletterElapsedMs(1000, 10000)).toBe(9000);
  });

  it('checks the address before sending', () => {
    expect(looksLikeNewsletterEmail('anna@example.org')).toBe(true);
    expect(looksLikeNewsletterEmail('anna@example')).toBe(false);
    expect(looksLikeNewsletterEmail('<anna>@example.org')).toBe(false);
    expect(looksLikeNewsletterEmail(`${'a'.repeat(250)}@example.org`)).toBe(false);
  });
});

describe('newsletter answer', () => {
  it('maps the status codes', () => {
    expect(newsletterOutcome(202, '{"status":"accepted"}')).toBe('accepted');
    expect(newsletterOutcome(202, '{"status":"accepted","code":"already_subscribed"}')).toBe('alreadySubscribed');
    expect(newsletterOutcome(422, '{"field":"email"}')).toBe('invalidEmail');
    expect(newsletterOutcome(422, '{"field":"consent"}')).toBe('unavailable');
    expect(newsletterOutcome(422, 'not json')).toBe('unavailable');
    expect(newsletterOutcome(429, '{}')).toBe('rateLimited');
    expect(newsletterOutcome(500, '{}')).toBe('unavailable');
  });

  it('posts JSON to the endpoint', async () => {
    const fetchImpl = vi.fn(async () => new Response('{"status":"accepted"}', { status: 202 }));
    const outcome = await subscribeToNewsletter('https://api.test/v1/newsletter/subscribe', '{"x":1}', fetchImpl);
    expect(outcome).toBe('accepted');
    expect(fetchImpl).toHaveBeenCalledWith('https://api.test/v1/newsletter/subscribe', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
      body: '{"x":1}',
    });
  });

  it('a network failure is offline', async () => {
    const fetchImpl = vi.fn(async () => {
      throw new TypeError('Failed to fetch');
    });
    expect(await subscribeToNewsletter('https://api.test', '{}', fetchImpl)).toBe('offline');
  });
});
