/**
 * Tests for the brand-glossary single-source-of-truth.
 *
 * Source of truth: `.scratch/seo-overhaul/prd.md` §D (Brand-Sprach-Mapping) +
 * `CONTEXT.md` §7 (Anti-Vokabular).
 *
 * The glossary is consumed by every marketing copy / i18n string / Schema
 * component on the site. The self-consistency check below locks in the one
 * invariant that protects every downstream consumer:
 *
 *   No canonical export string may itself appear as a forbidden term in the
 *   antiVocabulary list.
 *
 * If this test ever fails, the glossary contradicts itself and the site would
 * ship copy that violates the very brand-language rules it's supposed to
 * enforce.
 */
import { describe, expect, it } from "vitest";
import {
  actionDE,
  actionEN,
  antiVocabulary,
  outputArtifactDE,
  outputArtifactEN,
  productCategoryDE,
  productCategoryEN,
  verbDE,
  verbEN,
} from "../../data/brand-glossary.ts";

describe("brand-glossary", () => {
  it("never proposes a canonical term that is itself on the anti-vocabulary list", () => {
    const canonical = [
      productCategoryDE,
      productCategoryEN,
      actionDE,
      actionEN,
      outputArtifactDE,
      outputArtifactEN,
      verbDE,
      verbEN,
    ];
    const forbidden = antiVocabulary.map((entry) => entry.term.toLowerCase());

    for (const term of canonical) {
      // Each canonical export must not collide with any forbidden term —
      // case-insensitive, because the anti-vocabulary check on the rendered
      // site will be case-insensitive too.
      expect(forbidden, `canonical export "${term}" collides with anti-vocabulary`)
        .not.toContain(term.toLowerCase());
    }
  });

  it("structures every anti-vocabulary entry with term, replacement and rationale", () => {
    expect(antiVocabulary.length).toBeGreaterThan(0);
    for (const entry of antiVocabulary) {
      expect(typeof entry.term).toBe("string");
      expect(entry.term.length).toBeGreaterThan(0);
      expect(typeof entry.replacement).toBe("string");
      expect(typeof entry.rationale).toBe("string");
      expect(entry.rationale.length).toBeGreaterThan(0);
      if (entry.contrastiveAllowed !== undefined) {
        expect(typeof entry.contrastiveAllowed).toBe("boolean");
      }
    }
  });
});
