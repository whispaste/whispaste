/**
 * Guards for the provider name on the legal pages (#1774).
 *
 * The export to the public mirror rewrites the Sentry organisation slug with
 * a pattern that also matched the written-out GbR name, so the live imprint
 * showed "org …". These tests make sure no website source contains a line the
 * pattern can rewrite, that every translated privacy fragment still takes the
 * name from src/legal/entity.ts, and that the post-build check
 * (scripts/check-legal-entity.mjs) really fails on a rewritten page.
 */
import { mkdir, mkdtemp, readdir, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { PROVIDER_NAME, PROVIDER_NAME_PLACEHOLDER } from "../../src/legal/entity.ts";
import {
  EXPECTED_PROVIDER_NAME,
  LEGAL_PAGES,
  checkLegalEntity,
} from "../check-legal-entity.mjs";

/** Same pattern as the export's slug rule; any match goes public as "org". */
const EXPORT_SLUG_RULE = /silvio[-_ ]?lindstedt[-_ ]und[-_ ]maik[-_a-z0-9]*/gi;

const SRC = fileURLToPath(new URL("../../src/", import.meta.url));
const PRIVACY = join(SRC, "legal", "privacy");
const TEXT = /\.(astro|ts|tsx|mjs|js|html|md|mdx|json|css)$/;

async function textFiles(dir: string): Promise<string[]> {
  const out: string[] = [];
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) out.push(...(await textFiles(path)));
    else if (TEXT.test(entry.name)) out.push(path);
  }
  return out;
}

async function distWith(pages: Record<string, string>): Promise<string> {
  const dist = await mkdtemp(join(tmpdir(), "legal-entity-"));
  for (const [page, html] of Object.entries(pages)) {
    await mkdir(join(dist, page), { recursive: true });
    await writeFile(join(dist, page, "index.html"), html);
  }
  return dist;
}

describe("provider name", () => {
  it("is the full GbR name in the source and in the build check", () => {
    // Compared part by part: a literal full name here would itself be rewritten.
    expect(PROVIDER_NAME).toBe(EXPECTED_PROVIDER_NAME);
    expect(PROVIDER_NAME.split(" ")).toEqual([
      "Silvio",
      "Lindstedt",
      "und",
      "Maik",
      "Gräfendorf,",
      "GbR",
    ]);
  });

  it("is never written out where the export would rewrite it", async () => {
    const hits: string[] = [];
    for (const file of await textFiles(SRC)) {
      const text = await readFile(file, "utf8");
      for (const m of text.matchAll(EXPORT_SLUG_RULE)) hits.push(`${file}: ${m[0]}`);
    }
    expect(hits).toEqual([]);
  });

  it("comes from entity.ts in every translated privacy fragment", async () => {
    const fragments = (await readdir(PRIVACY)).filter((f) => f.endsWith(".html"));
    expect(fragments.length).toBeGreaterThan(0);
    for (const f of fragments) {
      const text = await readFile(join(PRIVACY, f), "utf8");
      expect(text.split(PROVIDER_NAME_PLACEHOLDER).length - 1, f).toBe(1);
    }
  });
});

describe("checkLegalEntity", () => {
  it("passes when every legal page shows the full name", async () => {
    const dist = await distWith(
      Object.fromEntries(LEGAL_PAGES.map((p) => [p, `<p>${EXPECTED_PROVIDER_NAME}<br>`])),
    );
    expect(checkLegalEntity(dist)).toEqual([]);
  });

  it("fails on a page the export rewrote and on a missing page", async () => {
    const dist = await distWith({
      impressum: "<p><strong>org Gräfendorf, GbR</strong><br>",
      datenschutz: `<p>${EXPECTED_PROVIDER_NAME}<br>`,
    });
    expect(checkLegalEntity(dist, ["impressum", "datenschutz", "en/impressum"])).toEqual([
      `impressum: provider name "${EXPECTED_PROVIDER_NAME}" not found`,
      "en/impressum: page missing from dist/",
    ]);
  });
});
