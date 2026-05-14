/**
 * Tests for {@link parseReleaseBody}.
 *
 * The public surface is the pure function `parseReleaseBody(markdown: string)`
 * which returns a `ReleaseBlocks` structure. Tests cover:
 *   - real GitHub release bodies (v1.2.10/11/12) via snapshot,
 *   - the documented section-classification rules,
 *   - the documented robustness cases (empty/unknown/no-heading inputs).
 */
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { describe, expect, it } from "vitest";
import { parseReleaseBody } from "../markdown-to-blocks.ts";

const fixturesDir = join(dirname(fileURLToPath(import.meta.url)), "fixtures");

function readFixture(name: string): string {
  return readFileSync(join(fixturesDir, name), "utf8");
}

describe("parseReleaseBody — real GitHub release bodies", () => {
  it("parses v1.2.10 body into stable block structure", () => {
    expect(parseReleaseBody(readFixture("v1.2.10.md"))).toMatchSnapshot();
  });

  it("parses v1.2.11 body into stable block structure", () => {
    expect(parseReleaseBody(readFixture("v1.2.11.md"))).toMatchSnapshot();
  });

  it("parses v1.2.12 body into stable block structure", () => {
    expect(parseReleaseBody(readFixture("v1.2.12.md"))).toMatchSnapshot();
  });
});

describe("parseReleaseBody — section classification", () => {
  it("recognises the Highlights section", () => {
    const result = parseReleaseBody("### Highlights\n- first\n- second\n");
    expect(result.sections).toHaveLength(1);
    expect(result.sections[0]?.heading).toBe("Highlights");
    expect(result.sections[0]?.items).toEqual([
      { body: "first" },
      { body: "second" },
    ]);
  });

  it("recognises Bug Fixes, Improvements, Removals, Observability headings", () => {
    const input = [
      "### Bug Fixes",
      "- fix one",
      "",
      "### Improvements",
      "- improve one",
      "",
      "### Removals",
      "- remove one",
      "",
      "### Observability",
      "- observe one",
      "",
    ].join("\n");
    const result = parseReleaseBody(input);
    expect(result.sections.map((s) => s.heading)).toEqual([
      "Bug Fixes",
      "Improvements",
      "Removals",
      "Observability",
    ]);
  });

  it("normalises the German Verbesserungen heading to Improvements", () => {
    const result = parseReleaseBody("### Verbesserungen\n- something better\n");
    expect(result.sections[0]?.heading).toBe("Improvements");
  });

  it("treats * bullets identically to - bullets", () => {
    const result = parseReleaseBody("### Highlights\n* star one\n* star two\n");
    expect(result.sections[0]?.items).toEqual([
      { body: "star one" },
      { body: "star two" },
    ]);
  });

  it("extracts a bold title prefix (**Title**: body) when present", () => {
    const result = parseReleaseBody(
      "### Bug Fixes\n- **Crash on quit**: closing the window no longer crashes.\n",
    );
    expect(result.sections[0]?.items).toEqual([
      {
        title: "Crash on quit",
        body: "closing the window no longer crashes.",
      },
    ]);
  });
});

describe("parseReleaseBody — robustness", () => {
  it("preserves an empty section's heading with an empty items array", () => {
    const result = parseReleaseBody("### Foo\n\n### Bar\n- one\n");
    expect(result.sections).toHaveLength(2);
    expect(result.sections[0]).toEqual({ heading: "Foo", items: [] });
    expect(result.sections[1]?.heading).toBe("Bar");
    expect(result.sections[1]?.items).toEqual([{ body: "one" }]);
  });

  it("keeps unknown section headings as-is (Other category)", () => {
    const result = parseReleaseBody(
      "### Internal Refactors\n- decomposed the orchestrator\n",
    );
    expect(result.sections).toHaveLength(1);
    expect(result.sections[0]?.heading).toBe("Internal Refactors");
    expect(result.sections[0]?.items).toEqual([
      { body: "decomposed the orchestrator" },
    ]);
  });

  it("wraps a plain paragraph body (no ### headings) into a default section", () => {
    const body =
      "Re-release of 1.2.0 with consistent version metadata and release\npipeline stabilization. No user-visible app changes.";
    const result = parseReleaseBody(body);
    expect(result.sections).toHaveLength(1);
    expect(result.sections[0]?.heading).toBe("Highlights");
    expect(result.sections[0]?.items).toHaveLength(1);
    expect(result.sections[0]?.items[0]?.body).toBe(body.trim());
  });

  it("returns an empty sections array for an empty input", () => {
    expect(parseReleaseBody("")).toEqual({ sections: [] });
    expect(parseReleaseBody("   \n\n  \n")).toEqual({ sections: [] });
  });

  it("is a pure function (no module-level state, repeated calls equivalent)", () => {
    const input = "### Highlights\n- one\n";
    const a = parseReleaseBody(input);
    const b = parseReleaseBody(input);
    expect(a).toEqual(b);
    // Returned objects are distinct references — caller may mutate freely.
    expect(a).not.toBe(b);
  });
});
