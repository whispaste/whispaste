/**
 * Client-side locale glue. Pages are server-rendered per locale, so nothing
 * here swaps text; it only honours `?lang=<locale>` deep links (used by the
 * desktop app) by navigating to the matching localised URL.
 */
import { alternatePaths, isLocale, parsePath } from './locales.ts';

export function applyLang(): void {
  const requested = new URLSearchParams(window.location.search).get('lang');
  if (!isLocale(requested)) return;
  const { pathname } = window.location;
  if (parsePath(pathname).locale === requested) return;
  const target = alternatePaths(pathname)[requested];
  if (target === pathname) return;
  // Keep a plain in-page anchor only; anything else in the fragment is dropped
  // so the redirect target stays a fixed same-origin route.
  const anchor = /^#[\w-]+$/.exec(window.location.hash)?.[0] ?? '';
  window.location.replace(`${target}${anchor}`);
}
