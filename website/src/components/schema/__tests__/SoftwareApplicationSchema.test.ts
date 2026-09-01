/**
 * Tests for `buildSoftwareApplicationSchema` — the JSON-LD builder behind
 * `<SoftwareApplicationSchema />`. The assertions encode the "saved validator
 * response" demanded by AC2 of Issue 04: instead of curl-ing an external
 * Schema.org validator on every CI run (slow, flaky, exhausts free-tier
 * quotas), we lock the shape contract here. The contract mirrors the
 * Schema.org `SoftwareApplication` spec plus Google's Rich-Results-eligibility
 * fields (name, operatingSystem, applicationCategory, offers).
 *
 * Manual one-time online verification is documented in the issue's
 * `decisions:` evidence block — paste the rendered `/` and `/en/` HTML into
 * https://validator.schema.org/ and https://search.google.com/test/rich-results
 * and archive the screenshot under `.scratch/seo-overhaul/evidence/`.
 */
import { describe, expect, it } from "vitest";
import {
  APPLICATION_ID,
  buildSoftwareApplicationSchema,
  DEFAULT_OPERATING_SYSTEMS,
  SCHEMA_CONTEXT,
} from "../builders.ts";

describe("buildSoftwareApplicationSchema", () => {
  it("DE variant: emits correct @context, @type, locale, and required Schema.org fields", () => {
    const schema = buildSoftwareApplicationSchema({ locale: "de" });

    expect(schema["@context"]).toBe(SCHEMA_CONTEXT);
    expect(schema["@type"]).toBe("SoftwareApplication");
    expect(schema["@id"]).toBe(APPLICATION_ID);
    expect(schema.name).toBe("WhisPaste");
    expect(schema.inLanguage).toBe("de-DE");
    expect(schema.url).toBe("https://whispaste.de/");
    expect(schema.applicationCategory).toBe("ProductivityApplication");
    // Google Rich Results requires operatingSystem, offers, and name as the
    // minimum trio for a "Software App" rich result.
    expect(typeof schema.operatingSystem).toBe("string");
    expect(schema.operatingSystem).toContain("Linux");
    expect(schema.offers).toMatchObject({ "@type": "Offer", price: "0" });
    // priceCurrency must be ABSENT — we ship a free MIT-licensed app, so the
    // earlier `USD` literal was incorrect and would cause a Validator notice.
    expect((schema.offers as Record<string, unknown>).priceCurrency).toBeUndefined();
    expect(schema.license).toBe("https://opensource.org/licenses/MIT");
    expect(Array.isArray(schema.screenshot)).toBe(true);
    // Nine motifs: five Flutter goldens plus the four real Windows-box
    // captures (06 Smart Mode … 09 side panel) added to the gallery.
    expect(schema.screenshot).toHaveLength(9);
    // DE screenshots must reference the `/de/` directory so the visible UI
    // language in the screenshot matches the locale-specific landing page.
    for (const url of schema.screenshot as readonly string[]) {
      expect(url).toMatch(/\/screenshots\/de\//);
    }
    // The localized description must use the canonical product term and
    // describe the two concrete landing-page promises.
    expect(typeof schema.description).toBe("string");
    expect(schema.description as string).toContain("Desktop-Sprach-Eingabe-Tool");
    expect(schema.description as string).toMatch(/lokal/i);
    expect(schema.description as string).toMatch(/Cursor/i);
    // featureList mirrors the visible FeatureHighlights cards (localized).
    expect(Array.isArray(schema.featureList)).toBe(true);
    expect(schema.featureList).toHaveLength(7);
    expect(schema.featureList as readonly string[]).toContain(
      "Smart Mode: bereinigen, kürzen, übersetzen",
    );
  });

  it("EN variant: switches inLanguage and url to en-US / /en/", () => {
    const schema = buildSoftwareApplicationSchema({ locale: "en" });

    expect(schema.inLanguage).toBe("en-US");
    expect(schema.url).toBe("https://whispaste.de/en/");
    expect(typeof schema.description).toBe("string");
    expect(schema.description as string).toMatch(/desktop voice-input tool/i);
    expect(schema.description as string).toMatch(/locally/i);
    expect(schema.description as string).toMatch(/cursor/i);
    for (const url of schema.screenshot as readonly string[]) {
      expect(url).toMatch(/\/screenshots\/en\//);
    }
    expect(schema.featureList as readonly string[]).toContain(
      "Smart Mode: clean up, shorten, translate",
    );
  });

  it("honours optional overrides for OS list, screenshots, and featureList", () => {
    const schema = buildSoftwareApplicationSchema({
      locale: "de",
      operatingSystems: ["Windows 11"],
      screenshots: ["https://example.test/shot.png"],
      featureList: ["One feature"],
    });
    expect(schema.operatingSystem).toBe("Windows 11");
    expect(schema.screenshot).toEqual(["https://example.test/shot.png"]);
    expect(schema.featureList).toEqual(["One feature"]);
  });

  it("defaults operatingSystem list covers Windows, macOS and Linux per PRD §C", () => {
    expect(DEFAULT_OPERATING_SYSTEMS.join(",")).toMatch(/Windows/);
    expect(DEFAULT_OPERATING_SYSTEMS.join(",")).toMatch(/macOS/);
    expect(DEFAULT_OPERATING_SYSTEMS.join(",")).toMatch(/Linux/);
  });
});
