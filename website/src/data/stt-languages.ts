/**
 * Dictation languages per local engine, mirrored from the app so the website
 * never claims more (or less) than the app offers:
 *   - Whisper:  `lib/core/config/whisper_languages.dart` (`whisperLanguages`,
 *               same order — roughly by training data, largest first)
 *   - Parakeet: `lib/services/stt_parakeet/parakeet_model_registry.dart`
 *               (`parakeetSupportedLanguages`, parakeet-tdt-0.6b-v3)
 * `src/data/__tests__/stt-languages.test.ts` fails when the two drift apart.
 * Codes are Whisper's; display names come from `Intl.DisplayNames` per locale.
 */
export const WHISPER_LANGUAGES = [
  'en', 'zh', 'de', 'es', 'ru', 'ko', 'fr', 'ja', 'pt', 'tr', 'pl', 'ca', 'nl', 'ar', 'sv', 'it',
  'id', 'hi', 'fi', 'vi', 'he', 'uk', 'el', 'ms', 'cs', 'ro', 'da', 'hu', 'ta', 'no', 'th', 'ur',
  'hr', 'bg', 'lt', 'la', 'mi', 'ml', 'cy', 'sk', 'te', 'fa', 'lv', 'bn', 'sr', 'az', 'sl', 'kn',
  'et', 'mk', 'br', 'eu', 'is', 'hy', 'ne', 'mn', 'bs', 'kk', 'sq', 'sw', 'gl', 'mr', 'pa', 'si',
  'km', 'sn', 'yo', 'so', 'af', 'oc', 'ka', 'be', 'tg', 'sd', 'gu', 'am', 'yi', 'lo', 'uz', 'fo',
  'ht', 'ps', 'tk', 'nn', 'mt', 'sa', 'lb', 'my', 'bo', 'tl', 'mg', 'as', 'tt', 'haw', 'ln', 'ha',
  'ba', 'jw', 'su',
] as const;

export const PARAKEET_LANGUAGES: ReadonlySet<string> = new Set([
  'bg', 'hr', 'cs', 'da', 'nl', 'en', 'et', 'fi', 'fr', 'de', 'el', 'hu', 'it',
  'lv', 'lt', 'mt', 'pl', 'pt', 'ro', 'sk', 'sl', 'es', 'sv', 'ru', 'uk',
]);

// Whisper uses the legacy code "jw" for Javanese; BCP 47 (and Intl) say "jv".
const BCP47: Record<string, string> = { jw: 'jv' };

/** BCP 47 tag for a Whisper code, for `lang` attributes and Intl lookups. */
export const bcp47 = (code: string): string => BCP47[code] ?? code;

/** Language name in the page's locale, e.g. ("de", "fr") → "Französisch". */
export function languageName(code: string, locale: string): string {
  const names = new Intl.DisplayNames([locale], { type: 'language', fallback: 'code' });
  return names.of(bcp47(code)) ?? code;
}
