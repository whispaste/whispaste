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
 * - The new copy never uses the forbidden donation vocabulary (internal-notes §7).
 */

const LOCALES = Object.keys(i18n) as (keyof typeof i18n)[];

const DIFF_KEYS = [
  "diff.label",
  "diff.title",
  "diff.baseline",
  ...["smartmode", "localAi"].flatMap((card) => [`diff.${card}.title`, `diff.${card}.body`]),
  "diff.smartmode.shotAlt",
  "diff.proof.screenshot",
  "diff.proof.faq",
  "diff.more",
];

// Lines that stand right next to a store button: per D-005 (#1949) none of
// them points to GitHub or the free variant.
const NEXT_TO_STORE_BUTTON = [
  "store.note.windows",
  "store.note.macos",
  "store.note.generic",
  "hero.cta.allDownloads",
];

const KEYS = [
  "explainer.whisperDesktop.heroNote",
  "contact.question.download",
  // Dictation + file transcription and both ways to get the app (#1937).
  "explainer.whisperDesktop.uses.heading",
  "explainer.whisperDesktop.uses.dictate.title",
  "explainer.whisperDesktop.uses.dictate.body",
  "explainer.whisperDesktop.uses.files.title",
  "explainer.whisperDesktop.uses.files.body",
  "explainer.whisperDesktop.get.heading",
  "explainer.whisperDesktop.get.lead",
  "explainer.whisperDesktop.get.free.title",
  "explainer.whisperDesktop.get.free.body",
  "explainer.whisperDesktop.get.free.cta",
  "explainer.whisperDesktop.get.store.title",
  "explainer.whisperDesktop.get.store.body",
  "explainer.whisperDesktop.get.store.price",
  "explainer.whisperDesktop.get.store.linux",
  "explainer.whisperDesktop.faq.files.q",
  "explainer.whisperDesktop.faq.files.a",
  "explainer.whisperDesktop.howTo.step4.name",
  "explainer.whisperDesktop.howTo.step4.text",
  "store.note.windows",
  "store.note.macos",
  "store.note.generic",
  "faq.whyPay.q",
  "faq.whyPay.a",
  "download.faq.title",
  // Differences block and the neutral download link next to the hero (#1949).
  "explainer.whisperDesktop.heroLead",
  "hero.cta.allDownloads",
  ...DIFF_KEYS,
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

      it("never names code signing or certificates as a use of the money", () => {
        for (const key of ["faq.whyPay.a", "store.perks.support.desc", "download.whyTwoWays.body2", "support.desc", "sponsor.costs.microsoft.desc"]) {
          expect(dict[key], key).not.toMatch(/code.?sign|signier|signatur|signing|zertifikat|certific|firma digital|сертификат|подписани|签名|证书/i);
        }
      });

      it("never claims every version has the same features", () => {
        // The MS Store build has no CUDA pack and the Mac App Store build has
        // sandbox limits, so the copy says "buying unlocks nothing" instead.
        for (const key of ["faq.whyPay.a", "faq.free.a", "store.perks.once.desc", "store.note.windows", "explainer.whisperDesktop.get.lead"]) {
          expect(dict[key], key).not.toMatch(/Kernfunktion|core feature|same feature|identi/i);
        }
      });

      it("lists the Mac App Store differences without a closing count", () => {
        // The sandbox list is open-ended ("for example"); a count like "two"
        // went stale once more differences were found (#1937 QA).
        for (const key of ["faq.free.a", "store.note.macos", "useCase.everyday.faq.cost.a", "explainer.whisperDesktop.faq.free.a"]) {
          expect(dict[key], key).not.toMatch(/\b(zwei|two|dos|duas|due|deux)\b|два|两|二/i);
        }
      });

      it("names no GitHub or free variant next to a store button (D-005)", () => {
        for (const key of NEXT_TO_STORE_BUTTON) {
          expect(dict[key], key).not.toMatch(/github|kostenlos|free|gratis|grátis|gratuit|бесплатн|免费/i);
        }
      });

      it("names the store comfort and the one-time price under the buttons", () => {
        for (const key of ["store.note.windows", "store.note.macos", "store.note.generic"]) {
          expect(dict[key], key).toMatch(/Store/);
        }
        expect(dict["store.note.windows"]).toMatch(/SmartScreen/);
      });

      it("claims no S mode, no signing and no language count as an advantage in the new block", () => {
        for (const key of [...DIFF_KEYS, "store.note.windows", "store.note.macos", "store.note.generic"]) {
          expect(dict[key], key).not.toMatch(/\bS[- ]?(mode|modus|模式)|signier|signed|signing|firmad|assinad|firmat|sign[ée]|подписан|подписью|签名|zertifik|certific|сертификат|证书|\b99\b/i);
        }
      });

      it("leads the hero line with the dictation, not with setup", () => {
        expect(dict["explainer.whisperDesktop.heroLead"]).not.toMatch(/^[^.。]*python/i);
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
