/**
 * Tests for `buildHowToSchema` — the JSON-LD builder behind `<HowToSchema />`.
 * Asserts the Schema.org `HowTo` shape, locale-correct `inLanguage`, and that
 * the default step list is non-empty with the required per-step fields
 * (Google Rich Results requires `name` and `text` on each `HowToStep`).
 */
import { describe, expect, it } from "vitest";
import {
  buildHowToSchema,
  defaultHowToStepsFor,
  SCHEMA_CONTEXT,
} from "../builders.ts";

describe("buildHowToSchema", () => {
  it("DE variant: emits required Schema.org fields with locale-correct strings", () => {
    const schema = buildHowToSchema({ locale: "de" });

    expect(schema["@context"]).toBe(SCHEMA_CONTEXT);
    expect(schema["@type"]).toBe("HowTo");
    expect(schema.inLanguage).toBe("de-DE");
    expect(typeof schema.name).toBe("string");
    expect((schema.name as string).length).toBeGreaterThan(0);
    expect(typeof schema.description).toBe("string");

    const steps = schema.step as readonly Record<string, unknown>[];
    expect(steps.length).toBeGreaterThan(0);
    steps.forEach((step, index) => {
      expect(step["@type"]).toBe("HowToStep");
      expect(step.position).toBe(index + 1);
      expect(typeof step.name).toBe("string");
      expect((step.name as string).length).toBeGreaterThan(0);
      expect(typeof step.text).toBe("string");
      expect((step.text as string).length).toBeGreaterThan(0);
    });
  });

  it("EN variant: switches inLanguage to en-US and pulls English step text", () => {
    const schema = buildHowToSchema({ locale: "en" });
    expect(schema.inLanguage).toBe("en-US");

    const steps = schema.step as readonly Record<string, unknown>[];
    // First default step (Press hotkey) — proves the i18n lookup landed in EN.
    expect((steps[0].name as string).toLowerCase()).toMatch(/hotkey|press/);
  });

  it("default step list contains the three documented setup steps", () => {
    expect(defaultHowToStepsFor("de")).toHaveLength(3);
    expect(defaultHowToStepsFor("en")).toHaveLength(3);
  });

  it("honours an explicit steps override", () => {
    const schema = buildHowToSchema({
      locale: "de",
      steps: [
        { name: "Schritt A", text: "Mach A." },
        { name: "Schritt B", text: "Mach B." },
      ],
    });
    const steps = schema.step as readonly Record<string, unknown>[];
    expect(steps).toHaveLength(2);
    expect(steps[0].name).toBe("Schritt A");
    expect(steps[1].position).toBe(2);
  });
});
