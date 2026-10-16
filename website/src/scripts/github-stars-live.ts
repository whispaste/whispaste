/**
 * Live update for the nav's GitHub pill. The page ships with the build-time
 * count (github-stars.ts); this asks our own API, which caches GitHub's value
 * server-side and survives its rate limits, so the visitor's browser never
 * talks to GitHub. Any failure leaves the rendered count untouched. One
 * answer per tab session is enough (sessionStorage, 10 minutes).
 */
import { formatStars } from './github-stars-format.ts';

const SESSION_KEY = 'wp-github-stars';
const SESSION_TTL = 10 * 60 * 1000;

function cached(): number | null {
  try {
    const value: unknown = JSON.parse(sessionStorage.getItem(SESSION_KEY) ?? 'null');
    if (value && typeof value === 'object' && 'count' in value && 'at' in value) {
      const { count, at } = value as { count: unknown; at: unknown };
      if (typeof count === 'number' && typeof at === 'number' && Date.now() - at < SESSION_TTL) return count;
    }
  } catch {
    // Storage blocked: just ask the API.
  }
  return null;
}

function remember(count: number): void {
  try {
    sessionStorage.setItem(SESSION_KEY, JSON.stringify({ count, at: Date.now() }));
  } catch {
    // Storage blocked: nothing to remember.
  }
}

function apply(count: number): void {
  for (const pill of document.querySelectorAll<HTMLElement>('[data-github-stars]')) {
    const lang = pill.dataset.lang ?? 'en';
    const value = pill.querySelector<HTMLElement>('[data-github-stars-value]');
    if (value) value.textContent = formatStars(count, lang);
    const stars = (pill.dataset.labelStars ?? '').replace('{count}', String(count));
    const label = `${pill.dataset.labelAria ?? 'GitHub'} · ${stars}`;
    pill.setAttribute('aria-label', label);
    pill.title = label;
  }
}

export async function refreshStars(): Promise<void> {
  const endpoint = document.querySelector<HTMLElement>('[data-stars-endpoint]')?.dataset.starsEndpoint;
  if (!endpoint) return;
  const known = cached();
  if (known) {
    apply(known);
    return;
  }
  try {
    const res = await fetch(endpoint, { headers: { Accept: 'application/json' }, signal: AbortSignal.timeout(4000) });
    if (!res.ok) return;
    const { count } = (await res.json()) as { count?: unknown };
    if (typeof count !== 'number' || count <= 0) return;
    remember(count);
    apply(count);
  } catch {
    // Offline, blocked or API down: the build-time count stays.
  }
}
