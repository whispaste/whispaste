import { describe, expect, it } from 'vitest';
import { i18n, SUPPORTED_LOCALES } from '../../src/scripts/i18n.ts';

// Every locale carries the coffee button label (same key, complete wording),
// and the label itself never uses the forbidden donation vocabulary.
const FORBIDDEN = /\bspenden?\b|donat|donaci|\bdonar\b|\bdoar\b|doação|\bdonazione|\bdonare\b|\bdon(?!['’])\b|\bun don\b|пожертв|捐助|捐款|捐赠/i;

describe('coffee button label', () => {
  for (const lang of SUPPORTED_LOCALES) {
    it(`${lang} has a non-empty coffee.label without donation wording`, () => {
      const label = i18n[lang]['coffee.label'];
      expect(label, `coffee.label missing in ${lang}`).toBeTruthy();
      expect(label).not.toMatch(FORBIDDEN);
    });
  }
});
