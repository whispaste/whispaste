/**
 * Keeps the original referrer across the site's own language redirects.
 *
 * The browser-language redirect (Layout.astro) and the `?lang=` deep link
 * (lang-switch.ts) navigate with `location.replace`. The browser then reports
 * whispaste.de itself as referrer on the target page, so Matomo filed search
 * and AI-assistant visits as self-referrals or "direct" (Matomo, Nov 2026:
 * 1,503 of 1,881 direct visits on site 4 had whispaste.de as referrer).
 *
 * Before redirecting, the page stores the referrer it arrived with in
 * sessionStorage (this tab only, never in a URL, never sent anywhere but to
 * Matomo, which would have received it without the redirect anyway). The
 * target page hands it to Matomo with `setReferrerUrl` before
 * `trackPageView` and deletes it. The entry only counts for the exact target
 * path and for a short time, so a later visit in the same tab never inherits
 * an old referrer.
 *
 * The Layout redirect is an inline script and writes the same JSON shape by
 * hand; keep both in step (tests/language-redirect.spec.ts checks it).
 */

export const REFERRER_CARRY_KEY = 'wp-ref';
export const REFERRER_CARRY_MAX_AGE_MS = 30_000;

export interface CarriedReferrer {
  /** `document.referrer` of the redirecting page ('' = direct entry). */
  readonly ref: string;
  /** Path the redirect leads to. */
  readonly to: string;
  /** Time of the redirect (ms since epoch). */
  readonly at: number;
}

/** Called right before a same-site redirect to `to` (a path). */
export function rememberReferrer(
  to: string,
  storage: Storage = window.sessionStorage,
  referrer: string = document.referrer,
  now: number = Date.now(),
): void {
  try {
    const entry: CarriedReferrer = { ref: referrer, to, at: now };
    storage.setItem(REFERRER_CARRY_KEY, JSON.stringify(entry));
  } catch {
    // Storage blocked: the visit keeps the self-referral, nothing breaks.
  }
}

/**
 * Inline JavaScript for the Matomo bootstrap (Layout.astro), placed before
 * `trackPageView`. Plain ES5 because it is emitted verbatim; `_paq` is the
 * queue declared just before it.
 */
export const APPLY_CARRIED_REFERRER_JS = `try {
    var carried = JSON.parse(sessionStorage.getItem("${REFERRER_CARRY_KEY}") || "null");
    sessionStorage.removeItem("${REFERRER_CARRY_KEY}");
    if (carried && typeof carried.ref === "string" && carried.to === location.pathname && Date.now() - carried.at < ${REFERRER_CARRY_MAX_AGE_MS}) {
      _paq.push(["setReferrerUrl", carried.ref]);
    }
  } catch (e) {}`;
