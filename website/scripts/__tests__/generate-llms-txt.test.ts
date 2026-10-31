/**
 * Guards for the `llms.txt` / `llms-full.txt` generator.
 *
 * The public files may only come from `website/llms/<locale>.md`: the
 * generator reads nothing else, the sources carry no internal references,
 * the brand vocabulary holds, and the committed outputs match the sources.
 */
import { readFile } from "node:fs/promises";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import {
  LLMS_LOCALES,
  LLMS_SOURCE_DIR,
  buildLlmsFullTxt,
  buildLlmsTxt,
  buildOutputs,
  defaultLlmsTxtInput,
  llmsSourcePath,
} from "../generate-llms-txt.mjs";
import { antiVocabulary } from "../../src/data/brand-glossary.ts";
import { scanHtml } from "../check-brand-vocabulary.mjs";

const WEBSITE_DIR = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");
const GENERATOR = join(WEBSITE_DIR, "scripts", "generate-llms-txt.mjs");

/** Traces of internal material that must never reach a public file. */
const INTERNAL_MARKERS = [
  /CONTEXT\.md/i,
  /zielgruppe\.md/i,
  /nordstern/i,
  /\internal-notes,
  /\bdocs\//i,
  /\bADR[ -]?\d/i,
  /\bTODO\b/,
  /seo-audit/i,
];

describe("source boundary", () => {
  it("reads only the public sources in website/llms", async () => {
    expect(relative(WEBSITE_DIR, LLMS_SOURCE_DIR)).toBe("llms");
    for (const locale of LLMS_LOCALES) {
      expect(dirname(llmsSourcePath(locale))).toBe(LLMS_SOURCE_DIR);
    }
    const code = await readFile(GENERATOR, "utf8");
    // One read in the whole generator, and it goes through llmsSourcePath.
    expect(code.match(/readFile\(/g)).toHaveLength(1);
    expect(code).toContain("readFile(llmsSourcePath(locale)");
    expect(code).not.toMatch(/CONTEXT\.md|zielgruppe|["'`]docs["'`/]|REPO_ROOT|\.\.["'`], ["'`]\.\./);
  });

  it("covers every website language", () => {
    expect([...LLMS_LOCALES].sort()).toEqual(["de", "en", "es", "fr", "it", "pt", "ru", "zh"]);
  });
});

describe("public content", () => {
  it("no output carries internal references or brand anti-vocabulary", async () => {
    const outputs = await buildOutputs();
    for (const [path, content] of Object.entries(outputs)) {
      for (const marker of INTERNAL_MARKERS) {
        expect(content, `${path} matches ${marker}`).not.toMatch(marker);
      }
      expect(scanHtml(content, antiVocabulary), path).toEqual([]);
    }
  });

  it("the committed files in public/ match the sources", async () => {
    const outputs = await buildOutputs();
    for (const [path, content] of Object.entries(outputs)) {
      const committed = await readFile(join(WEBSITE_DIR, "public", path), "utf8");
      expect(committed, `public/${path} is stale: run npm run gen:llms`).toBe(content);
    }
  });
});

describe("format", () => {
  it("llms.txt follows llmstxt.org and links every language", async () => {
    const { "llms.txt": index } = await buildOutputs();
    expect(index.split("\n")[0]).toBe("# WhisPaste");
    expect(index).toMatch(/\n> /);
    expect(index).toMatch(/- \[Download \(Deutsch\)\]\(https:\/\/whispaste\.de\/download\/\): /);
    for (const locale of LLMS_LOCALES) {
      expect(index).toContain(`(https://whispaste.de/llms/${locale}.md)`);
    }
  });

  it("buildLlmsTxt writes link lists with optional notes", () => {
    const out = buildLlmsTxt({
      title: "T",
      description: "D",
      sections: [{ title: "S", links: [{ label: "A", url: "https://a", note: "n" }, { label: "B", url: "https://b" }] }],
    });
    expect(out).toBe("# T\n\n> D\n\n## S\n\n- [A](https://a): n\n- [B](https://b)\n");
  });

  it("llms-full.txt keeps the given order, one block per language", () => {
    const out = buildLlmsFullTxt([
      { locale: "en", markdown: "# WhisPaste\n\nEnglish\n" },
      { locale: "de", markdown: "# WhisPaste\n\nDeutsch\n" },
    ]);
    expect(out).toBe("<!-- lang: en -->\n\n# WhisPaste\n\nEnglish\n\n---\n\n<!-- lang: de -->\n\n# WhisPaste\n\nDeutsch\n");
    expect(defaultLlmsTxtInput().title).toBe("WhisPaste");
  });
});
