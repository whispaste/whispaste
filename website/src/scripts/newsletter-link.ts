/**
 * Rules of the three newsletter link pages (confirm, unsubscribe, device):
 * what the address carries, which POST each page sends and which state each
 * answer of whispaste-api (internal-notes §3a) leads to. The page
 * changes nothing on load; only the button posts. Mail links carry a secret
 * token, so it is read once, kept in memory and removed from the address bar.
 */

import { isRetryLater } from './retry-later';

export type NewsletterAction = 'confirm' | 'unsubscribe' | 'device';

export const NEWSLETTER_ACTIONS: readonly NewsletterAction[] = ['confirm', 'unsubscribe', 'device'];

export const NEWSLETTER_API_DEFAULT = 'https://api.whispaste.de/v1/newsletter';

/** Longest wait shown for a rate limit; a larger `Retry-After` is not worth counting down. */
export const MAX_WAIT_SECONDS = 120;

/** The one POST gives up after this; a stalled connection must not leave the page in "sending" forever. */
export const SEND_TIMEOUT_MS = 15_000;

const TOKEN_SHAPE = /^[A-Za-z0-9._~-]{8,256}$/;

export interface LinkParams {
  /** The secret from the mail link, or null when absent or malformed. */
  token: string | null;
  /** `done=1`: the API redirected here after it had already done the work. */
  done: boolean;
  /** `app=1`: the sign-up came from the app, so the page offers the way back. */
  app: boolean;
}

export function parseLinkParams(search: string): LinkParams {
  const params = new URLSearchParams(search);
  const raw = params.get('token');
  return {
    token: raw !== null && TOKEN_SHAPE.test(raw) ? raw : null,
    done: params.get('done') === '1',
    app: params.get('app') === '1',
  };
}

/** The address without the token, so it neither stays in the history nor leaks later. */
export function withoutToken(search: string): string {
  const params = new URLSearchParams(search);
  params.delete('token');
  const rest = params.toString();
  return rest === '' ? '' : `?${rest}`;
}

export type PageState = 'ask' | 'sending' | 'done' | 'invalid' | 'broken' | 'limited' | 'network' | 'unavailable';

/** The state a page starts in, from what its address carries. */
export function initialState(params: LinkParams): PageState {
  if (params.done) return 'done';
  return params.token === null ? 'broken' : 'ask';
}

export function endpointFor(action: NewsletterAction, base: string = NEWSLETTER_API_DEFAULT): string {
  return `${base.replace(/\/+$/, '')}/${action}`;
}

export function requestBody(token: string): string {
  return JSON.stringify({ token });
}

export interface Outcome {
  state: PageState;
  /** Seconds until a retry makes sense (rate limit only). */
  waitSeconds?: number;
  /** The sign-up came from the app (confirm only). */
  app?: boolean;
}

/** Seconds from a `Retry-After` header; anything unusable becomes a short default. */
export function retryAfterSeconds(header: string | null): number {
  const n = Number.parseInt(header ?? '', 10);
  if (!Number.isFinite(n) || n < 1) return 30;
  return Math.min(n, MAX_WAIT_SECONDS);
}

/** Maps the answer of a POST to the state the page shows next. */
export function outcomeOf(status: number, body: unknown, retryAfter: string | null): Outcome {
  if (status === 200) {
    const app = (body as { app?: unknown } | null)?.app === true;
    return { state: 'done', app };
  }
  if (isRetryLater(status)) return { state: 'unavailable' };
  if (status === 429) return { state: 'limited', waitSeconds: retryAfterSeconds(retryAfter) };
  if (status === 400) return { state: 'invalid' };
  if (status === 422) return { state: 'broken' };
  return { state: 'network' };
}

/** Sends the one POST of a page; a thrown network error is a `network` outcome. */
export async function submitLink(
  action: NewsletterAction,
  token: string,
  fetchImpl: typeof fetch = fetch,
  base: string = NEWSLETTER_API_DEFAULT,
): Promise<Outcome> {
  try {
    const res = await fetchImpl(endpointFor(action, base), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: requestBody(token),
      referrerPolicy: 'no-referrer',
      credentials: 'omit',
      signal: AbortSignal.timeout(SEND_TIMEOUT_MS),
    });
    let body: unknown = null;
    try {
      body = await res.json();
    } catch {
      body = null;
    }
    return outcomeOf(res.status, body, res.headers.get('Retry-After'));
  } catch {
    return { state: 'network' };
  }
}

/**
 * The way back to the app. Device pages always offer it (internal-notes §2a); the
 * confirm page only for sign-ups that started in the app (§3).
 */
export function offersAppLink(action: NewsletterAction, app: boolean): boolean {
  return action === 'device' || (action === 'confirm' && app);
}

/** Page texts have `{seconds}` as the only placeholder. */
export function fillSeconds(template: string, seconds: number): string {
  return template.replace('{seconds}', String(seconds));
}
