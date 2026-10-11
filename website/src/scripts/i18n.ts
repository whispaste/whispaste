/**
 * Website translations: dictionaries per locale plus the `t()` helper.
 * Server-side only (it bundles every dictionary); client code imports
 * `locales.ts` instead. Locale registry and URL helpers are re-exported.
 */
import de from '../i18n/de.ts';
import en from '../i18n/en.ts';
import es from '../i18n/es.ts';
import it from '../i18n/it.ts';
import pt from '../i18n/pt.ts';
import ru from '../i18n/ru.ts';
import zh from '../i18n/zh.ts';

import { DEFAULT_LOCALE, isLocale, type Locale } from './locales.ts';

export * from './locales.ts';

export const i18n: Record<Locale, Record<string, string>> = { de, en, es, pt, it, ru, zh };

/**
 * Translation helper. Resolves `key` in `lang`, falls back to English and
 * finally to the raw key. Unknown locales resolve as the default locale.
 */
export function t(lang: string | undefined, key: string): string {
  const locale: Locale = isLocale(lang) ? lang : DEFAULT_LOCALE;
  return i18n[locale][key] ?? i18n.en[key] ?? key;
}
