import { describe, expect, it } from 'vitest';
import { i18n, SUPPORTED_LOCALES, t } from '../i18n.ts';

// Stage labels of the landing and sub-page panels (`art.label.<art>`, shown via
// `.wp-panel::before`). Every locale needs its own word; English leaking into
// DE/ES/… pages was LP-ART-LABEL-I18N.
const LABEL_KEYS = ['voice', 'hardware', 'privacy', 'hotkey', 'platforms', 'releases', 'community'].map(
  (art) => `art.label.${art}`,
);

describe('art stage labels', () => {
  for (const lang of SUPPORTED_LOCALES) {
    it(`${lang} has a non-empty value for every art label key`, () => {
      for (const key of LABEL_KEYS) {
        expect(i18n[lang][key], `${key} missing in ${lang}`).toBeTruthy();
      }
    });
  }

  it('German labels are German, not the English fallback', () => {
    expect(t('de', 'art.label.platforms')).toBe('Plattformen');
    expect(t('de', 'art.label.privacy')).toBe('Privatsphäre');
    expect(t('de', 'art.label.hotkey')).toBe('Tastenkürzel');
    expect(t('de', 'art.label.voice')).toBe('Stimme');
    expect(t('de', 'art.label.releases')).toBe('Versionen');
  });
});
