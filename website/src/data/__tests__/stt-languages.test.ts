import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import { PARAKEET_LANGUAGES, WHISPER_LANGUAGES, languageName } from '../stt-languages';

// The website's language grid must match what the app actually offers.
const repo = (path: string) => readFileSync(fileURLToPath(new URL(`../../../../${path}`, import.meta.url)), 'utf8');

/** Quoted map keys / set entries inside the Dart declaration that starts at `decl`. */
function dartCodes(source: string, decl: string): string[] {
  const start = source.indexOf(decl);
  expect(start, `${decl} not found`).toBeGreaterThanOrEqual(0);
  const body = source.slice(start, source.indexOf('};', start));
  return [...body.matchAll(/^\s*'([a-z]{2,3})'/gm)].map((m) => m[1]);
}

describe('stt-languages', () => {
  it('mirrors the app’s Whisper list in order', () => {
    const app = dartCodes(repo('lib/core/config/whisper_languages.dart'), 'const Map<String, String> whisperLanguages');
    expect(WHISPER_LANGUAGES).toEqual(app);
    expect(WHISPER_LANGUAGES).toHaveLength(99);
  });

  it('mirrors the app’s Parakeet set, all of it inside Whisper’s', () => {
    const app = dartCodes(repo('lib/services/stt_parakeet/parakeet_model_registry.dart'), 'const Set<String> parakeetSupportedLanguages');
    expect([...PARAKEET_LANGUAGES].sort()).toEqual([...app].sort());
    expect(PARAKEET_LANGUAGES.size).toBe(25);
    for (const code of PARAKEET_LANGUAGES) expect(WHISPER_LANGUAGES).toContain(code);
  });

  it('names every language in every site locale (no raw codes)', () => {
    for (const locale of ['de', 'en', 'es', 'pt', 'it', 'ru', 'zh', 'fr']) {
      for (const code of WHISPER_LANGUAGES) {
        const name = languageName(code, locale);
        expect(name, `${code} in ${locale}`).not.toBe(code);
      }
    }
    expect(languageName('jw', 'de')).toBe('Javanisch');
  });
});
