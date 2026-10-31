/**
 * Tests for `buildBreadcrumbListSchema` — the JSON-LD builder behind
 * `<BreadcrumbListSchema />`. Asserts the Schema.org-mandated structure of
 * `BreadcrumbList` plus the 1-based contiguous `position` numbering (Google
 * Rich Results rejects breadcrumbs with non-contiguous positions).
 */
import { describe, expect, it } from "vitest";
import {
  buildBreadcrumbListSchema,
  SCHEMA_CONTEXT,
  SITE_ORIGIN,
} from "../builders.ts";

describe("buildBreadcrumbListSchema", () => {
  it("DE variant: home → datenschutz with absolute URLs and contiguous positions", () => {
    const schema = buildBreadcrumbListSchema({
      items: [
        { name: "Start", item: "/" },
        { name: "Datenschutz", item: "/datenschutz/" },
      ],
    });

    expect(schema["@context"]).toBe(SCHEMA_CONTEXT);
    expect(schema["@type"]).toBe("BreadcrumbList");
    const items = schema.itemListElement as readonly Record<string, unknown>[];
    expect(items).toHaveLength(2);

    // 1-based positions, contiguous.
    expect(items[0].position).toBe(1);
    expect(items[1].position).toBe(2);

    // Required Schema.org fields per ListItem.
    for (const entry of items) {
      expect(entry["@type"]).toBe("ListItem");
      expect(typeof entry.name).toBe("string");
      expect(typeof entry.item).toBe("string");
      // Absolutized — Google Rich Results requires absolute `item` URLs for
      // breadcrumb entries (or full HTTP URLs).
      expect(entry.item as string).toMatch(new RegExp(`^${SITE_ORIGIN}`));
    }

    expect(items[0].name).toBe("Start");
    expect(items[1].name).toBe("Datenschutz");
  });

  it("EN variant: home → privacy with /en/ URLs", () => {
    const schema = buildBreadcrumbListSchema({
      items: [
        { name: "Home", item: "/en/" },
        { name: "Privacy Policy", item: "/en/privacy/" },
      ],
    });
    const items = schema.itemListElement as readonly Record<string, unknown>[];
    expect(items[0].item).toBe(`${SITE_ORIGIN}/en/`);
    expect(items[1].item).toBe(`${SITE_ORIGIN}/en/privacy/`);
  });

  it("passes already-absolute URLs through unchanged", () => {
    const ext = "https://example.test/elsewhere/";
    const schema = buildBreadcrumbListSchema({
      items: [
        { name: "Home", item: "/" },
        { name: "External", item: ext },
      ],
    });
    const items = schema.itemListElement as readonly Record<string, unknown>[];
    expect(items[1].item).toBe(ext);
  });

  it("assigns positions starting at 1 and incrementing by 1 for any length", () => {
    const schema = buildBreadcrumbListSchema({
      items: [
        { name: "A", item: "/a/" },
        { name: "B", item: "/b/" },
        { name: "C", item: "/c/" },
        { name: "D", item: "/d/" },
      ],
    });
    const positions = (
      schema.itemListElement as readonly Record<string, unknown>[]
    ).map((entry) => entry.position);
    expect(positions).toEqual([1, 2, 3, 4]);
  });
});
