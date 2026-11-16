/**
 * Shape of `/faq-match/<locale>.json` (#352), shared by the build endpoint
 * and the contact widget. Free of dictionaries, safe for client code.
 */
import type { FaqIndex } from './engine.ts';

export interface FaqMatchData {
  readonly index: FaqIndex;
  /** FAQ key → question line and answer text of this locale. */
  readonly faq: Readonly<Record<string, { readonly q: string; readonly a: string }>>;
}

/** URL of the matcher data for one locale. */
export function faqMatchUrl(locale: string): string {
  return `/faq-match/${locale}.json`;
}
