/**
 * Tests für den `llms.txt`/`llms-full.txt`-Generator (`generate-llms-txt.mjs`).
 *
 * Geprüfte Pure-Funktionen:
 *   - `extractSections(markdown, numbers)` — pickt `## n.`-Sektionen aus dem
 *     Markdown und konkateniert sie deterministisch.
 *   - `buildLlmsTxt({ title, description, sections })` — produziert die
 *     llmstxt.org-konforme Kurzversion.
 *   - `buildLlmsFullTxt({ contextSections, zielgruppeMd })` — konkateniert
 *     CONTEXT.md §1–§4 und docs/zielgruppe.md.
 *
 * Tests verwenden Mock-Markdown statt der echten PROTECTED-Quelldateien,
 * damit die Specs auch in einer frischen CI-Clone-Umgebung laufen. Die
 * Brand-Vocabulary-Konformität des Outputs wird gegen die echte
 * `antiVocabulary`-Tabelle aus `brand-glossary.ts` verifiziert, damit das
 * Issue 02 CI-Gate auch für `llms.txt`/`llms-full.txt` greift.
 */
import { describe, expect, it } from "vitest";
import {
  buildLlmsFullTxt,
  buildLlmsTxt,
  defaultLlmsTxtInput,
  extractSections,
} from "../generate-llms-txt.mjs";
import { antiVocabulary } from "../../src/data/brand-glossary.ts";
import { buildTermRegex, scanHtml } from "../check-brand-vocabulary.mjs";

const MOCK_CONTEXT_MD = `# CONTEXT.md — Mock

> Pflege-Regel.

---

## 1. Produktkern

WhisPaste ist ein voice-input tool.

---

## 2. Kernbegriffe

### 2.1 Aufnahme-Vorgang

Der Aufnahme-Vorgang läuft.

---

## 3. Pipeline-Vokabular

Phasen: idle → recording → transcribing.

---

## 4. STT-Vokabular

Provider, Engine, Modell, Backend.

---

## 5. UI-Vokabular

Diese Sektion soll NICHT im Output erscheinen.

---

## 6. Konzeptuelle Entscheidungen

Auch diese nicht.
`;

const MOCK_ZIELGRUPPE_MD = `# Zielgruppe — Mock

Vielschreibende Desktop-Nutzer.
`;

describe("extractSections", () => {
  it("returns only the requested numbered sections in order", () => {
    const out = extractSections(MOCK_CONTEXT_MD, [1, 2, 3, 4]);
    expect(out).toContain("## 1. Produktkern");
    expect(out).toContain("## 2. Kernbegriffe");
    expect(out).toContain("## 3. Pipeline-Vokabular");
    expect(out).toContain("## 4. STT-Vokabular");
    expect(out).not.toContain("## 5. UI-Vokabular");
    expect(out).not.toContain("## 6. Konzeptuelle");
  });

  it("preserves the order of requested sections even when input is differently ordered", () => {
    const md = `## 2. Two\n\nbody two\n\n## 1. One\n\nbody one\n`;
    const out = extractSections(md, [1, 2]);
    const idx1 = out.indexOf("## 1. One");
    const idx2 = out.indexOf("## 2. Two");
    expect(idx1).toBeGreaterThanOrEqual(0);
    expect(idx2).toBeGreaterThan(idx1);
  });

  it("silently skips missing sections", () => {
    const md = `## 1. Only\n\nbody\n`;
    const out = extractSections(md, [1, 2, 3, 4]);
    expect(out).toContain("## 1. Only");
    expect(out).not.toContain("## 2.");
  });

  it("strips trailing `---` separators from each section", () => {
    const out = extractSections(MOCK_CONTEXT_MD, [1]);
    expect(out.trimEnd().endsWith("---")).toBe(false);
  });
});

describe("buildLlmsTxt", () => {
  it("matches the expected llmstxt.org format (H1 + blockquote + section linklists)", () => {
    const out = buildLlmsTxt({
      title: "WhisPaste",
      description: "WhisPaste is an MIT-licensed voice-input tool.",
      sections: [
        {
          title: "Download",
          links: [
            { label: "Download", url: "https://whispaste.de/download/", note: "Microsoft Store" },
          ],
        },
        {
          title: "FAQ",
          links: [{ label: "FAQ", url: "https://whispaste.de/#faq" }],
        },
      ],
    });
    expect(out).toMatchSnapshot();
  });

  it("starts with `# <title>` on the first line", () => {
    const out = buildLlmsTxt(defaultLlmsTxtInput());
    expect(out.split("\n")[0]).toBe("# WhisPaste");
  });

  it("includes a blockquote description on a line starting with `> `", () => {
    const out = buildLlmsTxt(defaultLlmsTxtInput());
    expect(out).toMatch(/\n> /);
  });

  it("emits section headers as `## <title>` with markdown link lists below", () => {
    const out = buildLlmsTxt(defaultLlmsTxtInput());
    expect(out).toMatch(/\n## Download\n/);
    expect(out).toMatch(/\n## FAQ\n/);
    expect(out).toMatch(/\n## Privacy\n/);
    expect(out).toMatch(/\n## Comparisons\n/);
    // Linklist entries follow llmstxt.org convention: `- [label](url)` with optional `: note`.
    expect(out).toMatch(/- \[Download \(Deutsch\)\]\(https:\/\/whispaste\.de\/download\/\): /);
  });
});

describe("buildLlmsFullTxt", () => {
  it("concatenates the context sections and the audience document with a separator", () => {
    const sections = extractSections(MOCK_CONTEXT_MD, [1, 2, 3, 4]);
    const out = buildLlmsFullTxt({
      contextSections: sections,
      zielgruppeMd: MOCK_ZIELGRUPPE_MD,
    });
    expect(out).toMatchSnapshot();
  });

  it("contains both source bodies and orders them context-first, audience-second", () => {
    const sections = extractSections(MOCK_CONTEXT_MD, [1, 2, 3, 4]);
    const out = buildLlmsFullTxt({
      contextSections: sections,
      zielgruppeMd: MOCK_ZIELGRUPPE_MD,
    });
    const idxContext = out.indexOf("## 1. Produktkern");
    const idxAudience = out.indexOf("Vielschreibende Desktop-Nutzer");
    expect(idxContext).toBeGreaterThan(0);
    expect(idxAudience).toBeGreaterThan(idxContext);
  });

  it("does not include sections beyond the requested range", () => {
    const sections = extractSections(MOCK_CONTEXT_MD, [1, 2, 3, 4]);
    const out = buildLlmsFullTxt({
      contextSections: sections,
      zielgruppeMd: MOCK_ZIELGRUPPE_MD,
    });
    expect(out).not.toContain("## 5. UI-Vokabular");
    expect(out).not.toContain("## 6. Konzeptuelle");
  });
});

describe("brand vocabulary compliance (Issue 02 gate)", () => {
  it("default llms.txt output contains zero anti-vocabulary violations", () => {
    const out = buildLlmsTxt(defaultLlmsTxtInput());
    const findings = scanHtml(out, antiVocabulary);
    expect(findings).toEqual([]);
  });

  it("llms-full.txt built from a clean mock has zero anti-vocabulary violations", () => {
    const sections = extractSections(MOCK_CONTEXT_MD, [1, 2, 3, 4]);
    const out = buildLlmsFullTxt({
      contextSections: sections,
      zielgruppeMd: MOCK_ZIELGRUPPE_MD,
    });
    const findings = scanHtml(out, antiVocabulary);
    expect(findings).toEqual([]);
  });

  it("buildTermRegex catches a planted anti-vocab term in llms.txt-style output", () => {
    // Sanity check: if a future regression sneaks `dictation` into the
    // hardcoded description, the scan must catch it. (`dictation` is a
    // contrastive-allowed term in the live glossary, but the scanner sees
    // it as a finding outside contrastive markers — which is exactly the
    // production behaviour for `dist/llms.txt`.)
    const planted =
      "# WhisPaste\n\n> This is a dictation tool.\n\n## Download\n\n- [D](https://x)\n";
    const findings = scanHtml(planted, antiVocabulary);
    expect(findings.length).toBeGreaterThan(0);
    expect(findings[0].term).toBe("dictation");
    // The regex builder is the same one production uses — confirm it for
    // record-keeping in this spec.
    expect(buildTermRegex("dictation").flags).toContain("i");
  });
});
