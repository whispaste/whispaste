import { describe, expect, it } from "vitest";

import { i18n } from "../../scripts/i18n.ts";

/**
 * whisper-desktop-copy.test.ts — GR-037 to GR-041 copy rules, checked for all
 * 8 site languages from the dictionaries (no browser needed):
 *
 * - <title> and meta description start with the brand WhisPaste and stay
 *   within search-result lengths.
 * - The one-sentence line under the H1 and the CTA labels exist in every
 *   language.
 * - The new copy never uses the forbidden donation vocabulary (CONTEXT.md §7).
 */

const LOCALES = Object.keys(i18n) as (keyof typeof i18n)[];

const KEYS = [
  "explainer.whisperDesktop.heroNote",
  "explainer.whisperDesktop.cta.label",
  "explainer.whisperDesktop.cta.macos",
  "explainer.whisperDesktop.cta.windows",
  "explainer.whisperDesktop.cta.linux",
  "explainer.whisperDesktop.cta.github",
  "contact.question.download",
] as const;

// Spende and its equivalents in the site languages (brand-glossary.ts).
const FORBIDDEN = /spend|donat|donaz|doaç|пожертв|捐/i;

describe("whisper-desktop copy", () => {
  it("covers all 8 site languages", () => {
    expect(LOCALES.sort()).toEqual(["de", "en", "es", "fr", "it", "pt", "ru", "zh"]);
  });

  for (const lang of LOCALES) {
    describe(lang, () => {
      const dict = i18n[lang];

      it("starts the title with WhisPaste and keeps it search-friendly", () => {
        const title = dict["explainer.whisperDesktop.seoTitle"];
        expect(title).toMatch(/^WhisPaste/);
        expect(title.length).toBeLessThanOrEqual(60);
      });

      it("starts the meta description with WhisPaste and keeps it snippet-sized", () => {
        const description = dict["explainer.whisperDesktop.seoDescription"];
        expect(description).toMatch(/^WhisPaste/);
        expect(description.length).toBeLessThanOrEqual(160);
      });

      it("has every new explainer and widget string, non-empty", () => {
        for (const key of KEYS) {
          expect(dict[key], key).toBeTruthy();
        }
      });

      it("uses no donation vocabulary in the new strings", () => {
        for (const key of KEYS) {
          expect(dict[key], key).not.toMatch(FORBIDDEN);
        }
        expect(dict["explainer.whisperDesktop.seoTitle"]).not.toMatch(FORBIDDEN);
        expect(dict["explainer.whisperDesktop.seoDescription"]).not.toMatch(FORBIDDEN);
      });
    });
  }
});
