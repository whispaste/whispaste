import { describe, expect, it, vi } from 'vitest';
import {
  endpointFor,
  fillSeconds,
  initialState,
  offersAppLink,
  outcomeOf,
  parseLinkParams,
  requestBody,
  retryAfterSeconds,
  submitLink,
  withoutToken,
} from '../newsletter-link';
import { NEWSLETTER_PAGE_TEXTS, type NewsletterPageLocale } from '../../data/newsletter-pages-texts';

const TOKEN = ['link', 'token', 'sample'].join('-');
const asFetch = (fn: unknown) => fn as typeof fetch;

describe('parseLinkParams', () => {
  it('reads token, done and app', () => {
    expect(parseLinkParams(`?token=${TOKEN}&lang=de`)).toEqual({ token: TOKEN, done: false, app: false });
    expect(parseLinkParams('?done=1&app=1')).toEqual({ token: null, done: true, app: true });
  });

  it('treats a malformed token as missing', () => {
    expect(parseLinkParams('?token=short').token).toBeNull();
    expect(parseLinkParams('?token=has space and <tags>').token).toBeNull();
    expect(parseLinkParams('').token).toBeNull();
  });
});

describe('withoutToken', () => {
  it('removes only the token', () => {
    expect(withoutToken(`?token=${TOKEN}&lang=de`)).toBe('?lang=de');
    expect(withoutToken(`?token=${TOKEN}`)).toBe('');
  });
});

describe('initialState', () => {
  it('asks with a token, is done after the redirect, is broken otherwise', () => {
    expect(initialState({ token: TOKEN, done: false, app: false })).toBe('ask');
    expect(initialState({ token: null, done: true, app: false })).toBe('done');
    expect(initialState({ token: null, done: false, app: false })).toBe('broken');
  });
});

describe('outcomeOf', () => {
  it('maps every status of the contract', () => {
    expect(outcomeOf(200, { state: 'confirmed', app: true }, null)).toEqual({ state: 'done', app: true });
    expect(outcomeOf(200, null, null)).toEqual({ state: 'done', app: false });
    expect(outcomeOf(400, null, null).state).toBe('invalid');
    expect(outcomeOf(422, null, null).state).toBe('broken');
    expect(outcomeOf(429, null, '15')).toEqual({ state: 'limited', waitSeconds: 15 });
    expect(outcomeOf(500, null, null).state).toBe('network');
  });
});

describe('retryAfterSeconds', () => {
  it('caps large values and falls back for unusable ones', () => {
    expect(retryAfterSeconds('3600')).toBe(120);
    expect(retryAfterSeconds(null)).toBe(30);
    expect(retryAfterSeconds('soon')).toBe(30);
  });
});

describe('submitLink', () => {
  it('posts the token as JSON without referrer or cookies', async () => {
    const fetchImpl = vi.fn(async () => new Response(JSON.stringify({ state: 'unsubscribed' })));
    const out = await submitLink('unsubscribe', TOKEN, asFetch(fetchImpl), 'https://x.test/v1/newsletter/');
    expect(out.state).toBe('done');
    const [url, init] = fetchImpl.mock.calls[0] as unknown as [string, Parameters<typeof fetch>[1] & object];
    expect(url).toBe('https://x.test/v1/newsletter/unsubscribe');
    expect(init.method).toBe('POST');
    expect(init.body).toBe(requestBody(TOKEN));
    expect(init.referrerPolicy).toBe('no-referrer');
    expect(init.credentials).toBe('omit');
    expect(init.signal).toBeInstanceOf(AbortSignal);
  });

  it('turns a network failure into the network state', async () => {
    const fetchImpl = vi.fn(async () => {
      throw new TypeError('failed');
    });
    expect((await submitLink('confirm', TOKEN, asFetch(fetchImpl))).state).toBe('network');
  });

  it('reads Retry-After from a 429', async () => {
    const fetchImpl = vi.fn(async () => new Response('{}', { status: 429, headers: { 'Retry-After': '9' } }));
    expect(await submitLink('device', TOKEN, asFetch(fetchImpl))).toEqual({ state: 'limited', waitSeconds: 9 });
  });
});

describe('helpers', () => {
  it('builds endpoints and fills the wait', () => {
    expect(endpointFor('confirm')).toBe('https://api.whispaste.de/v1/newsletter/confirm');
    expect(fillSeconds('in {seconds} s', 7)).toBe('in 7 s');
  });
});

describe('offersAppLink', () => {
  it('offers the way back to the app on device pages and on app sign-ups only', () => {
    expect(offersAppLink('device', false)).toBe(true);
    expect(offersAppLink('confirm', true)).toBe(true);
    expect(offersAppLink('confirm', false)).toBe(false);
    expect(offersAppLink('unsubscribe', true)).toBe(false);
  });
});

describe('page texts', () => {
  const KEYS = Object.keys(NEWSLETTER_PAGE_TEXTS.de).sort();
  const LOCALES = Object.keys(NEWSLETTER_PAGE_TEXTS) as NewsletterPageLocale[];

  it('every locale carries exactly the keys of the German text', () => {
    for (const locale of LOCALES) {
      expect(Object.keys(NEWSLETTER_PAGE_TEXTS[locale]).sort(), locale).toEqual(KEYS);
    }
  });

  it('only the wait text has a placeholder, and it keeps {seconds}', () => {
    for (const locale of LOCALES) {
      const texts = NEWSLETTER_PAGE_TEXTS[locale];
      expect(texts['page.limited.wait'], locale).toContain('{seconds}');
      for (const [key, value] of Object.entries(texts)) {
        if (key !== 'page.limited.wait') expect(value, `${locale} ${key}`).not.toContain('{seconds}');
      }
    }
  });
});
