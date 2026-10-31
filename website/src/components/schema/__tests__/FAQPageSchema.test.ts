/**
 * Tests for `buildFAQPageSchema` — the JSON-LD builder behind
 * `<FAQPageSchema />`. Two source branches need coverage per the issue
 * brief: (a) explicit `questions` prop, (b) `questionKeys` (or default keys)
 * via the i18n lookup.
 */
import { describe, expect, it } from "vitest";
import {
  buildFAQPageSchema,
  DEFAULT_FAQ_KEYS,
  SCHEMA_CONTEXT,
} from "../builders.ts";

describe("buildFAQPageSchema", () => {
  it("DE variant: explicit `questions` prop produces locale-correct schema", () => {
    const schema = buildFAQPageSchema({
      locale: "de",
      questions: [
        { question: "Was ist WhisPaste?", answer: "Eine Sprachtaste." },
      ],
    });

    expect(schema["@context"]).toBe(SCHEMA_CONTEXT);
    expect(schema["@type"]).toBe("FAQPage");
    expect(schema.inLanguage).toBe("de-DE");

    const entities = schema.mainEntity as readonly Record<string, unknown>[];
    expect(entities).toHaveLength(1);
    expect(entities[0]).toMatchObject({
      "@type": "Question",
      name: "Was ist WhisPaste?",
      acceptedAnswer: {
        "@type": "Answer",
        text: "Eine Sprachtaste.",
      },
    });
  });

  it("EN variant: default `questionKeys` branch pulls answers from i18n", () => {
    const schema = buildFAQPageSchema({ locale: "en" });
    expect(schema.inLanguage).toBe("en-US");

    const entities = schema.mainEntity as readonly Record<string, unknown>[];
    // Default key list is non-empty and produces one entity per key.
    expect(entities.length).toBe(DEFAULT_FAQ_KEYS.length);

    for (const entity of entities) {
      expect(entity["@type"]).toBe("Question");
      expect(typeof entity.name).toBe("string");
      expect((entity.name as string).length).toBeGreaterThan(0);
      const answer = entity.acceptedAnswer as Record<string, unknown>;
      expect(answer["@type"]).toBe("Answer");
      expect(typeof answer.text).toBe("string");
      expect((answer.text as string).length).toBeGreaterThan(0);
    }
  });

  it("custom `questionKeys` subset maps to i18n keys", () => {
    const schema = buildFAQPageSchema({
      locale: "de",
      questionKeys: ["free", "offline"],
    });
    const entities = schema.mainEntity as readonly Record<string, unknown>[];
    expect(entities).toHaveLength(2);
    // i18n lookup landed (no raw key fallback like `faq.free.q`).
    for (const entity of entities) {
      expect(entity.name as string).not.toMatch(/^faq\./);
    }
  });

  it("`questions` prop wins over `questionKeys`", () => {
    const schema = buildFAQPageSchema({
      locale: "de",
      questions: [{ question: "Q?", answer: "A." }],
      questionKeys: ["free", "offline"],
    });
    expect((schema.mainEntity as readonly unknown[]).length).toBe(1);
  });
});
