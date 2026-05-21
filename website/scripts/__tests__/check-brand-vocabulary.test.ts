/**
 * Tests für den Anti-Vokabular-CI-Gate (`check-brand-vocabulary.mjs`).
 *
 * Geprüfte Pure-Funktionen:
 *   - `scanHtml(html, vocab)` — liefert deterministische Verstoß-Liste.
 *   - `stripContrastive(html)` — entfernt markierte Vergleichs-Sektionen
 *     und erhält die Zeilennummerierung des restlichen HTML.
 *   - `buildTermRegex(term)` — case-insensitive, ASCII-Wörter mit `\b`,
 *     Bindestrich-/Nicht-ASCII-Begriffe ohne `\b`.
 *
 * Tests verwenden ein dediziertes Test-Vokabular statt der echten
 * `antiVocabulary`-Tabelle, damit der Test stabil bleibt, wenn das Glossar
 * sich erweitert. Das Verhalten am echten Glossar wird durch den
 * `build:check`-Lauf in der CI abgedeckt.
 */
import { mkdir, mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import {
  CONTRASTIVE_CLOSE,
  CONTRASTIVE_OPEN,
  TXT_ALLOWLIST,
  buildTermRegex,
  scanHtml,
  stripContrastive,
  walkDistFiles,
  walkStoreFiles,
} from "../check-brand-vocabulary.mjs";

interface VocabEntry {
  term: string;
  replacement: string;
  rationale: string;
  contrastiveAllowed?: boolean;
}

const VOCAB: ReadonlyArray<VocabEntry> = [
  {
    term: "dictation",
    replacement: "voice-input tool",
    rationale: "Produkttyp",
    contrastiveAllowed: true,
  },
  {
    term: "Diktat",
    replacement: "Transkript",
    rationale: "Artefakt",
    contrastiveAllowed: true,
  },
  {
    term: "Diktier-Tool",
    replacement: "Sprach-Eingabe-Tool",
    rationale: "Produkttyp DE",
  },
];

describe("scanHtml", () => {
  it("returns at least one violation when the HTML contains a forbidden term", () => {
    const html = "<p>WhisPaste is a great dictation app.</p>";
    const findings = scanHtml(html, VOCAB);
    expect(findings.length).toBeGreaterThan(0);
    expect(findings[0]).toMatchObject({
      term: "dictation",
      replacement: "voice-input tool",
    });
  });

  it("returns zero violations when the forbidden term is inside a contrastive marker block", () => {
    const html = `<p>WhisPaste ist Open Source.</p>
${CONTRASTIVE_OPEN}
<p>WhisPaste ist keine Diktiersoftware und produziert keine Diktate.</p>
<p>Auch das englische "dictation" zählt hier nicht.</p>
${CONTRASTIVE_CLOSE}
<p>Schluss.</p>`;
    const findings = scanHtml(html, VOCAB);
    expect(findings).toEqual([]);
  });

  it("returns zero violations on a clean HTML string", () => {
    const html = "<p>WhisPaste is a voice-input tool that produces transcripts.</p>";
    const findings = scanHtml(html, VOCAB);
    expect(findings).toEqual([]);
  });

  it("reports line and column for each violation, in document order", () => {
    const html = ["<p>line one</p>", "<p>this is dictation</p>", "<p>here is Diktat too</p>"].join(
      "\n",
    );
    const findings = scanHtml(html, VOCAB);
    expect(findings).toHaveLength(2);
    expect(findings[0]).toMatchObject({ term: "dictation", line: 2 });
    expect(findings[1]).toMatchObject({ term: "Diktat", line: 3 });
  });

  it("only catches violations outside contrastive blocks when the document mixes both", () => {
    const html = `<p>Bad dictation here.</p>
${CONTRASTIVE_OPEN}
<p>Allowed: dictation comparison.</p>
${CONTRASTIVE_CLOSE}
<p>Another bad Diktat.</p>`;
    const findings = scanHtml(html, VOCAB);
    expect(findings.map((f) => f.term)).toEqual(["dictation", "Diktat"]);
  });

  it("matches case-insensitively for ASCII terms", () => {
    const html = "<p>DICTATION in caps.</p>";
    const findings = scanHtml(html, VOCAB);
    expect(findings).toHaveLength(1);
    expect(findings[0]).toMatchObject({ term: "dictation", match: "DICTATION" });
  });
});

describe("buildTermRegex", () => {
  it("anchors ASCII words at word boundaries to prevent false positives", () => {
    const re = buildTermRegex("dictation");
    expect(re.test("WhisPaste is a dictation app")).toBe(true);
    re.lastIndex = 0;
    expect(re.test("predicationary")).toBe(false);
  });

  it("matches non-ASCII / hyphenated terms without word boundaries", () => {
    const re = buildTermRegex("Diktier-Tool");
    expect(re.test("Vorgestellt: Diktier-Tool für alle.")).toBe(true);
  });

  it("is case-insensitive", () => {
    const re = buildTermRegex("Diktat");
    expect(re.test("DIKTAT")).toBe(true);
    re.lastIndex = 0;
    expect(re.test("diktat")).toBe(true);
  });
});

describe("walkDistFiles", () => {
  it("includes HTML plus the explicit `.txt` allowlist (`llms.txt`, `llms-full.txt`, `ai.txt`)", async () => {
    const root = await mkdtemp(join(tmpdir(), "brand-walk-"));
    await writeFile(join(root, "index.html"), "<html></html>");
    await writeFile(join(root, "llms.txt"), "# WhisPaste\n");
    await writeFile(join(root, "llms-full.txt"), "# Full\n");
    await writeFile(join(root, "ai.txt"), "Policy: allow\n");
    // A non-allowlisted .txt file (e.g. robots.txt) must NOT be picked up.
    await writeFile(join(root, "robots.txt"), "User-agent: *\n");
    // Nested HTML is walked recursively.
    await mkdir(join(root, "sub"));
    await writeFile(join(root, "sub", "page.html"), "<html></html>");
    const files = await walkDistFiles(root);
    const rels = files.map((f) => f.slice(root.length + 1));
    expect(rels).toContain("index.html");
    expect(rels).toContain("sub/page.html");
    expect(rels).toContain("llms.txt");
    expect(rels).toContain("llms-full.txt");
    expect(rels).toContain("ai.txt");
    expect(rels).not.toContain("robots.txt");
  });

  it("silently omits .txt allowlist entries that don't exist yet", async () => {
    const root = await mkdtemp(join(tmpdir(), "brand-walk-empty-"));
    await writeFile(join(root, "index.html"), "<html></html>");
    const files = await walkDistFiles(root);
    expect(files.map((f) => f.slice(root.length + 1))).toEqual(["index.html"]);
  });

  it("exposes the .txt allowlist as a frozen constant that includes ai.txt", () => {
    expect(Array.from(TXT_ALLOWLIST)).toEqual([
      "llms.txt",
      "llms-full.txt",
      "ai.txt",
    ]);
    expect(Object.isFrozen(TXT_ALLOWLIST)).toBe(true);
  });
});

describe("scanHtml on Markdown sources (store/**.md, Issue 15)", () => {
  // Der Scanner ist text-pattern-basiert; `scanHtml` heißt nur historisch so
  // und funktioniert genauso auf Markdown wie auf HTML. Die folgenden Cases
  // verifizieren, dass die Store-Markdown-Quellen (siehe Issue 15) durch
  // dieselbe Pipeline laufen — inklusive funktionierendem Kontrastiv-Marker,
  // weil Markdown HTML-Kommentare verbatim erlaubt.

  it("flags a forbidden term inside a Markdown paragraph", () => {
    const md = [
      "# WhisPaste — Microsoft Store long description",
      "",
      "WhisPaste is a great dictation app for daily writing.",
      "",
      "- Works in any app.",
    ].join("\n");
    const findings = scanHtml(md, VOCAB);
    expect(findings.length).toBeGreaterThan(0);
    expect(findings[0]).toMatchObject({
      term: "dictation",
      line: 3,
      replacement: "voice-input tool",
    });
  });

  it("respects the contrastive marker inside Markdown (HTML comments work verbatim)", () => {
    const md = [
      "# WhisPaste",
      "",
      "WhisPaste is a voice-input tool that produces transcripts.",
      "",
      CONTRASTIVE_OPEN,
      "WhisPaste is **not** a dictation app, and it is not a Diktier-Tool either.",
      CONTRASTIVE_CLOSE,
      "",
      "Privacy first.",
    ].join("\n");
    const findings = scanHtml(md, VOCAB);
    expect(findings).toEqual([]);
  });

  it("preserves Markdown line numbers in citations across mixed scopes", () => {
    const md = [
      "## Tagline",
      "",
      "Press, speak, done — no dictation, no friction.",
      "",
      "## Long description",
      "",
      CONTRASTIVE_OPEN,
      "An allowed Diktat mention in a contrastive block.",
      CONTRASTIVE_CLOSE,
      "",
      "Another bad Diktat after the block.",
    ].join("\n");
    const findings = scanHtml(md, VOCAB);
    expect(findings.map((f) => ({ term: f.term, line: f.line }))).toEqual([
      { term: "dictation", line: 3 },
      { term: "Diktat", line: 11 },
    ]);
  });
});

describe("walkStoreFiles", () => {
  it("returns only top-level *.md files under store/, sorted", async () => {
    const root = await mkdtemp(join(tmpdir(), "brand-store-"));
    await writeFile(
      join(root, "microsoft-store-long-description.md"),
      "# Long\n",
    );
    await writeFile(join(root, "dmg-distribution.md"), "# DMG\n");
    // Non-md files at top level must be ignored — Partner Center *.txt
    // snippets live in locale subfolders and are not part of the Markdown
    // scan scope.
    await writeFile(join(root, "README.md"), "# Readme\n");
    await writeFile(join(root, "notes.txt"), "should be ignored\n");
    // Subfolder content (e.g. store/de-DE/description.txt) is out of scope
    // for this scanner and must not be collected.
    await mkdir(join(root, "de-DE"));
    await writeFile(join(root, "de-DE", "description.txt"), "DE text\n");
    await writeFile(join(root, "de-DE", "nested.md"), "# nested\n");
    const files = await walkStoreFiles(root);
    const rels = files.map((f) => f.slice(root.length + 1));
    expect(rels).toEqual([
      "README.md",
      "dmg-distribution.md",
      "microsoft-store-long-description.md",
    ]);
  });

  it("returns an empty list when the store directory does not exist", async () => {
    const missing = join(tmpdir(), `brand-store-missing-${Date.now()}`);
    const files = await walkStoreFiles(missing);
    expect(files).toEqual([]);
  });
});

describe("stripContrastive", () => {
  it("removes content between paired markers", () => {
    const html = `before
${CONTRASTIVE_OPEN}
secret dictation
${CONTRASTIVE_CLOSE}
after`;
    const stripped = stripContrastive(html);
    expect(stripped).not.toContain("secret dictation");
    expect(stripped).toContain("before");
    expect(stripped).toContain("after");
  });

  it("preserves line counts so post-marker line numbers stay stable", () => {
    const html = ["<p>line 1</p>", CONTRASTIVE_OPEN, "<p>line 3 dictation</p>", CONTRASTIVE_CLOSE, "<p>line 5 Diktat</p>"].join(
      "\n",
    );
    const findings = scanHtml(html, VOCAB);
    // The contrastive `dictation` is filtered; the post-marker `Diktat` must
    // still report line 5 — not line 2 or 3.
    expect(findings).toHaveLength(1);
    expect(findings[0]).toMatchObject({ term: "Diktat", line: 5 });
  });

  it("is a no-op when no opening marker is present", () => {
    const html = "<p>plain html</p>";
    expect(stripContrastive(html)).toBe(html);
  });
});
