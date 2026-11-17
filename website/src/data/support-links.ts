/**
 * Support providers of the website: one entry per external way to support
 * WhisPaste with money, in the order of the sponsoring guide (one-time without
 * an account, coffee, monthly). This is the single website source for the
 * provider URLs; `src/data/__tests__/support-links.test.ts` compares it with
 * the app (`lib/core/app_urls.dart`), `.github/FUNDING.yml` and `README.md`, so the copies
 * cannot drift apart.
 *
 * `id` names the i18n keys (`sponsor.<id>.title|subtitle|desc|cta`), the logo
 * in `src/assets/support/<logo>.svg` and the brand tokens
 * (`--wp-support-tile-<id>-*`).
 */
export const PAYPAL_URL = 'https://www.paypal.com/donate/?hosted_button_id=GY8ZQQGJB9XPY';
export const KOFI_URL = 'https://ko-fi.com/silviol';
export const BUY_ME_A_COFFEE_URL = 'https://buymeacoffee.com/silvio.lindstedt';
export const GITHUB_SPONSORS_URL = 'https://github.com/sponsors/silvio-l';

export type SupportProviderId = 'paypal' | 'kofi' | 'buymeacoffee' | 'github';

export interface SupportProvider {
  readonly id: SupportProviderId;
  /** Brand name, never translated. */
  readonly name: string;
  readonly href: string;
  /** File name in src/assets/support/ without extension. */
  readonly logo: string;
}

export const SUPPORT_PROVIDERS: readonly SupportProvider[] = [
  { id: 'paypal', name: 'PayPal', href: PAYPAL_URL, logo: 'paypal' },
  { id: 'kofi', name: 'Ko-fi', href: KOFI_URL, logo: 'kofi' },
  { id: 'buymeacoffee', name: 'Buy Me a Coffee', href: BUY_ME_A_COFFEE_URL, logo: 'buymeacoffee' },
  { id: 'github', name: 'GitHub Sponsors', href: GITHUB_SPONSORS_URL, logo: 'githubsponsors' },
];
