/**
 * Tests for `buildOrganizationSchema` — the JSON-LD builder behind
 * `<OrganizationSchema />`. See `SoftwareApplicationSchema.test.ts` for the
 * rationale on "saved validator response" snapshot contracts (AC2/AC3).
 */
import { describe, expect, it } from "vitest";
import {
  buildOrganizationSchema,
  GITHUB_REPO_URL,
  ORGANIZATION_ID,
  ORGANIZATION_SAME_AS,
  SCHEMA_CONTEXT,
} from "../builders.ts";

describe("buildOrganizationSchema", () => {
  it("DE variant: emits correct @context, @type, @id and url", () => {
    const schema = buildOrganizationSchema({ locale: "de" });

    expect(schema["@context"]).toBe(SCHEMA_CONTEXT);
    expect(schema["@type"]).toBe("Organization");
    expect(schema["@id"]).toBe(ORGANIZATION_ID);
    expect(schema.name).toBe("WhisPaste");
    expect(schema.url).toBe("https://whispaste.de/");
    expect(schema.logo).toMatch(/\.png$/);
    expect(schema.sameAs).toEqual(ORGANIZATION_SAME_AS);
    expect((schema.sameAs as readonly string[])[0]).toBe(GITHUB_REPO_URL);
  });

  it("EN variant: switches url to /en/ but keeps the same @id (site-wide identity)", () => {
    const schema = buildOrganizationSchema({ locale: "en" });

    expect(schema.url).toBe("https://whispaste.de/en/");
    // The Organization @id must stay constant across locales so search engines
    // consolidate the entity. The Organization node is locale-neutral on purpose.
    expect(schema["@id"]).toBe(ORGANIZATION_ID);
  });

  it("accepts an explicit sameAs override without mutating the module constant", () => {
    const custom = ["https://example.test/profile"] as const;
    const schema = buildOrganizationSchema({ locale: "de", sameAs: custom });
    expect(schema.sameAs).toEqual(custom);
    // Source of truth must remain untouched (immutable readonly array).
    expect(ORGANIZATION_SAME_AS[0]).toBe(GITHUB_REPO_URL);
  });
});
