/**
 * Rules of the newsletter sign-up page: what the form sends to
 * `POST /v1/newsletter/subscribe` (whispaste-api, double opt-in) and what
 * each answer means for the page. The address only lives in the request;
 * the page stores nothing.
 */

import { isRetryLater } from './retry-later';

/**
 * The consent wording on the page (`newsletter.consent` in every locale) is
 * the API's text for this version, word for word. The server refuses any
 * other value; a new wording comes with a new version from the API.
 */
export const NEWSLETTER_CONSENT_VERSION = 'newsletter-2026-10-31';

/** The server drops faster sends as automated, so the page never sends below it. */
export const NEWSLETTER_MIN_FILL_IN_MS = 2500;

export const NEWSLETTER_ENDPOINT_DEFAULT = 'https://api.whispaste.de/v1/newsletter/subscribe';

const EMAIL_FORMAT = /^[^@\s<>"]+@[^@\s<>"]+\.[^@\s<>"]+$/;

/** A first check before anything is sent; the server has the final word. */
export function looksLikeNewsletterEmail(value: string): boolean {
  const email = value.trim();
  return email.length <= 254 && EMAIL_FORMAT.test(email);
}

/**
 * Milliseconds between showing the form and sending it, never below the
 * server's automation bar: a person who pastes an address and sends at once
 * would otherwise see the confirmation step but get no mail.
 */
export function newsletterElapsedMs(shownAt: number, now: number): number {
  return Math.max(NEWSLETTER_MIN_FILL_IN_MS, Math.round(now - shownAt));
}

/** The JSON body of one sign-up from the website. */
export function newsletterRequestBody(input: {
  email: string;
  locale: string;
  elapsedMs: number;
  honeypot: string;
}): string {
  return JSON.stringify({
    email: input.email.trim(),
    source: 'web',
    consent: NEWSLETTER_CONSENT_VERSION,
    locale: input.locale,
    website: input.honeypot,
    elapsed: input.elapsedMs,
  });
}

export type NewsletterOutcome = 'accepted' | 'alreadySubscribed' | 'invalidEmail' | 'rateLimited' | 'offline' | 'unavailable';

/** Maps the server's answer to what the page shows. */
export function newsletterOutcome(status: number, body: string): NewsletterOutcome {
  if (status === 202) return problemCode(body) === 'already_subscribed' ? 'alreadySubscribed' : 'accepted';
  if (isRetryLater(status)) return 'unavailable';
  if (status === 429) return 'rateLimited';
  if (status === 422 && problemField(body) === 'email') return 'invalidEmail';
  return 'unavailable';
}

function problemCode(body: string): string | null {
  try {
    const parsed: unknown = JSON.parse(body);
    if (parsed !== null && typeof parsed === 'object' && 'code' in parsed) {
      const code = (parsed as { code: unknown }).code;
      return typeof code === 'string' ? code : null;
    }
  } catch {
    // Not JSON: an old answer without a code means a normal sign-up.
  }
  return null;
}

function problemField(body: string): string | null {
  try {
    const parsed: unknown = JSON.parse(body);
    if (parsed !== null && typeof parsed === 'object' && 'field' in parsed) {
      const field = (parsed as { field: unknown }).field;
      return typeof field === 'string' ? field : null;
    }
  } catch {
    // Not JSON: treated as any other refusal.
  }
  return null;
}

/** One sign-up; a network failure is `offline`, never an exception. */
export async function subscribeToNewsletter(
  endpoint: string,
  body: string,
  fetchImpl: typeof fetch = fetch,
): Promise<NewsletterOutcome> {
  try {
    const res = await fetchImpl(endpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
      body,
    });
    return newsletterOutcome(res.status, await res.text());
  } catch {
    return 'offline';
  }
}
