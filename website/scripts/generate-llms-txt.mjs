#!/usr/bin/env node
/**
 * `llms.txt` / `llms-full.txt`-Generator — Build-time-Foundation für die KI-
 * Suche (siehe `.scratch/seo-overhaul/prd.md` §D, Issue 05).
 *
 * Quelldateien:
 *   - `<repo>/CONTEXT.md` — Domänen-Glossar (§1–§4 fließen in `llms-full.txt`).
 *   - `<repo>/docs/zielgruppe.md` — Zielgruppen-Definition (vollständig).
 *
 * Outputs (statisch, committet — siehe Designentscheidung unten):
 *   - `website/public/llms.txt` — kuratierte Kurzversion nach llmstxt.org-
 *     Konvention (H1-Title, Blockquote, Markdown-Linklisten pro Sektion).
 *   - `website/public/llms-full.txt` — Konkatenation von CONTEXT.md §1–§4 +
 *     docs/zielgruppe.md mit klaren Sektions-Trennern.
 *
 * Aufruf: `node scripts/generate-llms-txt.mjs` (typischerweise als Pre-Build-
 * Step über das `build`-Script in `package.json` ausgeführt). Vor dem
 * eigentlichen `astro build`-Lauf, damit Astro die generierten Public-Files
 * unverändert nach `dist/` kopiert.
 *
 * --- Design-Entscheidung: Output-Files sind committet ---------------------
 *
 * `CONTEXT.md` und `docs/` sind im WhisPaste-Repo gitignored (PROTECTED-
 * Section + pre-commit-Hook), bestehen also lokal auf der Maintainer-Maschine,
 * fehlen aber in einer frischen CI-Clone-Umgebung. Damit der CI-Build trotzdem
 * funktioniert, ist die Strategie:
 *
 *   1. Quelldateien vorhanden → frisch generieren und nach `public/` schreiben.
 *      Der Maintainer committet die Outputs in `website/public/llms.txt` und
 *      `website/public/llms-full.txt`.
 *   2. Quelldateien fehlen (CI) → Warnung loggen, beibehalten was im Repo
 *      schon vorhanden ist (kein Schreibvorgang), Exit 0.
 *
 * So bleibt CI grün, ohne dass PROTECTED-Inhalte ins Repo gelangen, und die
 * Produktions-Outputs spiegeln immer den letzten Maintainer-Generate-Lauf.
 *
 * Die reinen Builder-Funktionen sind exportiert und werden von Vitest unter
 * `__tests__/generate-llms-txt.test.ts` ohne Filesystem-Zugriffe verifiziert.
 */

import { readFile, writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

// ---------------------------------------------------------------------------
// Pure helpers (testable in isolation)
// ---------------------------------------------------------------------------

/**
 * Extrahiert die nummerierten Top-Level-Sektionen (`## 1.`, `## 2.`, …) aus
 * einem Markdown-Dokument und konkateniert sie in der angegebenen Reihenfolge
 * zu einem String.
 *
 * Sektions-Erkennungs-Regel: eine Zeile, die mit `## <n>.` beginnt, eröffnet
 * Sektion `<n>`. Die Sektion endet beim nächsten `## `-Header (egal welcher
 * Nummer) oder am Dokument-Ende. Trenner (`---`-Linien) am unmittelbaren
 * Sektions-Ende werden entfernt, damit die Konkatenation keine vagabundierenden
 * Trenner-Reihen einsammelt; CONTEXT.md selbst trennt §1–§4 mit `---`-Linien.
 *
 * @param {string} markdown - Quell-Markdown (typischerweise CONTEXT.md).
 * @param {ReadonlyArray<number>} sectionNumbers - Liste der zu extrahierenden
 *   Sektionsnummern in Output-Reihenfolge (z. B. `[1, 2, 3, 4]`).
 * @returns {string} Konkateniertes Markdown, Sektionen durch eine Leerzeile
 *   getrennt. Fehlende Sektionen werden stillschweigend ausgelassen.
 */
export function extractSections(markdown, sectionNumbers) {
  const sections = new Map();
  const lines = markdown.split("\n");
  let currentSection = null;
  let currentBuffer = [];
  for (const line of lines) {
    const headerMatch = /^##\s+(\d+)\./.exec(line);
    if (headerMatch) {
      if (currentSection !== null) {
        sections.set(currentSection, trimTrailingSeparators(currentBuffer));
      }
      currentSection = Number.parseInt(headerMatch[1], 10);
      currentBuffer = [line];
    } else if (currentSection !== null) {
      currentBuffer.push(line);
    }
  }
  if (currentSection !== null) {
    sections.set(currentSection, trimTrailingSeparators(currentBuffer));
  }
  const out = [];
  for (const n of sectionNumbers) {
    const buf = sections.get(n);
    if (!buf || buf.length === 0) continue;
    if (out.length > 0) out.push("");
    out.push(buf.join("\n").trimEnd());
  }
  return out.join("\n");
}

function trimTrailingSeparators(lines) {
  const buf = lines.slice();
  while (buf.length > 0) {
    const last = buf[buf.length - 1];
    if (last.trim() === "" || /^-{3,}\s*$/.test(last.trim())) {
      buf.pop();
    } else {
      break;
    }
  }
  return buf;
}

/**
 * Baut die kuratierte `llms.txt` nach der llmstxt.org-Konvention. Format:
 *
 *   # <title>
 *
 *   > <description>
 *
 *   ## <section title>
 *
 *   - [<link text>](<url>): <optional description>
 *
 * Der Output ist deterministisch und enthält keinen Anti-Vokabular-Treffer
 * (siehe Issue 02 Brand-Vocabulary-Gate).
 *
 * @param {object} input
 * @param {string} input.title - Produkt-Name als H1.
 * @param {string} input.description - Ein-Satz-Beschreibung im Blockquote.
 * @param {ReadonlyArray<{ title: string, links: ReadonlyArray<{ label: string, url: string, note?: string }> }>} input.sections
 *   Sektionen mit ihren Linklisten in Output-Reihenfolge.
 * @returns {string} Vollständige llms.txt mit abschließendem Newline.
 */
export function buildLlmsTxt({ title, description, sections }) {
  const lines = [];
  lines.push(`# ${title}`);
  lines.push("");
  lines.push(`> ${description}`);
  for (const section of sections) {
    lines.push("");
    lines.push(`## ${section.title}`);
    lines.push("");
    for (const link of section.links) {
      const noteSuffix = link.note ? `: ${link.note}` : "";
      lines.push(`- [${link.label}](${link.url})${noteSuffix}`);
    }
  }
  lines.push("");
  return lines.join("\n");
}

/**
 * Baut die `llms-full.txt`: vollständige Self-Beschreibung als Konkatenation
 * von CONTEXT.md §1–§4 und docs/zielgruppe.md. Beide Quellen werden mit einer
 * `---`-Trennlinie und Sektions-Überschriften verbunden, damit ein Modell die
 * beiden Blöcke unterscheiden kann.
 *
 * @param {object} input
 * @param {string} input.contextSections - bereits extrahierte CONTEXT.md-
 *   Sektionen (z. B. via `extractSections(contextMd, [1,2,3,4])`).
 * @param {string} input.zielgruppeMd - Roh-Inhalt von `docs/zielgruppe.md`.
 * @param {string} [input.generatedAt] - optionaler ISO-Timestamp für das
 *   Header-Frontmatter; Default: keine Frontmatter.
 * @returns {string} Vollständige llms-full.txt mit abschließendem Newline.
 */
export function buildLlmsFullTxt({ contextSections, zielgruppeMd, generatedAt }) {
  const lines = [];
  lines.push("# WhisPaste — Full LLM Reference");
  lines.push("");
  lines.push(
    "> Vollständige Self-Beschreibung von WhisPaste für KI-Suchmaschinen und LLM-Crawler. Quelle: `CONTEXT.md` §1–§4 + `docs/zielgruppe.md`.",
  );
  if (generatedAt) {
    lines.push("");
    lines.push(`<!-- generated: ${generatedAt} -->`);
  }
  // Der gesamte Body ist inhärent kontrastiv: CONTEXT.md §1 enthält explizit
  // die „WhisPaste ist nicht …"-Abgrenzungs-Tabelle, §2.6 und §7 listen das
  // Anti-Vokabular selbst auf, und `docs/zielgruppe.md` benennt unter
  // „Nicht optimieren für" die abgegrenzten Konzepte. Diese Begriffe MÜSSEN
  // im Dokument vorkommen — sie sind das Material, gegen das WhisPaste sich
  // definiert. Die kontrastiven Marker (siehe Issue 02) sind genau für
  // diesen Fall vorgesehen.
  lines.push("");
  lines.push("<!-- seo-audit:contrastive -->");
  lines.push("");
  lines.push("---");
  lines.push("");
  lines.push("## Part 1 — Domain Glossary (CONTEXT.md §1–§4)");
  lines.push("");
  lines.push(contextSections.trimEnd());
  lines.push("");
  lines.push("---");
  lines.push("");
  lines.push("## Part 2 — Target Audience (docs/zielgruppe.md)");
  lines.push("");
  lines.push(zielgruppeMd.trimEnd());
  lines.push("");
  lines.push("<!-- /seo-audit:contrastive -->");
  lines.push("");
  return lines.join("\n");
}

/**
 * Liest eine Quelldatei und gibt `null` zurück, wenn sie nicht existiert.
 * Andere Fehler werden weitergeworfen, damit der CI-Lauf bei echten I/O-
 * Problemen explizit failt (kein silent-success).
 *
 * @param {string} path
 * @returns {Promise<string | null>}
 */
export async function readOptional(path) {
  try {
    return await readFile(path, "utf8");
  } catch (err) {
    if (err && /** @type {NodeJS.ErrnoException} */ (err).code === "ENOENT") {
      return null;
    }
    throw err;
  }
}

// ---------------------------------------------------------------------------
// llms.txt — kanonische Sektionen + Links
// ---------------------------------------------------------------------------

/**
 * Kuratierte Sektionen für `llms.txt`. Hard-coded statt aus i18n-Strings
 * synthetisiert, weil `llms.txt` ein bewusster, von Hand kuratierter
 * Crawl-Einstiegspunkt ist (siehe llmstxt.org).
 */
const LLMS_TXT_SECTIONS = Object.freeze([
  {
    title: "Download",
    links: [
      {
        label: "Download (Deutsch)",
        url: "https://whispaste.de/download/",
        note: "Microsoft Store, DMG für macOS, oder kostenlos von GitHub",
      },
      {
        label: "Download (English)",
        url: "https://whispaste.de/en/download/",
        note: "Microsoft Store, macOS DMG, or free from GitHub",
      },
    ],
  },
  {
    title: "FAQ",
    links: [
      {
        label: "FAQ (Deutsch)",
        url: "https://whispaste.de/#faq",
        note: "Antworten zu Offline-Modus, Modellen, Genauigkeit, Datenschutz",
      },
      {
        label: "FAQ (English)",
        url: "https://whispaste.de/en/#faq",
        note: "Answers about offline mode, models, accuracy, privacy",
      },
    ],
  },
  {
    title: "Privacy",
    links: [
      {
        label: "Datenschutz (Deutsch)",
        url: "https://whispaste.de/datenschutz/",
        note: "Audio bleibt lokal; optionales opt-in für Cloud-Provider",
      },
      {
        label: "Privacy (English)",
        url: "https://whispaste.de/en/privacy/",
        note: "Audio stays local; cloud providers are opt-in",
      },
    ],
  },
  {
    title: "Comparisons",
    links: [
      {
        label: "Screenshots (Deutsch)",
        url: "https://whispaste.de/screenshots/",
        note: "Visueller Einblick in die App-Oberfläche",
      },
      {
        label: "Screenshots (English)",
        url: "https://whispaste.de/en/screenshots/",
        note: "Visual tour of the app surface",
      },
    ],
  },
  {
    title: "Source & Releases",
    links: [
      {
        label: "GitHub Repository",
        url: "https://github.com/silvio-lindstedt/whispaste",
        note: "MIT-licensed source, releases, and issue tracker",
      },
      {
        label: "Changelog (Deutsch)",
        url: "https://whispaste.de/changelog/",
        note: "Versionshistorie",
      },
      {
        label: "Changelog (English)",
        url: "https://whispaste.de/en/changelog/",
        note: "Release history",
      },
    ],
  },
]);

/**
 * Kuratierte Description für `llms.txt`. Folgt PRD §D-Brand-Sprache: explizit
 * `voice-input tool`, MIT-Lizenz, drei Desktop-Plattformen.
 */
const LLMS_TXT_TITLE = "WhisPaste";
const LLMS_TXT_DESCRIPTION =
  "WhisPaste is an MIT-licensed voice-input tool for Windows, macOS, and Linux that transcribes speech locally via whisper.cpp and inserts the transcript at the cursor position of the active application. iOS and Android are planned.";

/**
 * Liefert die default-Section-Liste, die `main()` für den Production-Build
 * verwendet. Exportiert, damit Tests den exakten Builder-Aufruf reproduzieren
 * können, ohne die Section-Definition zu duplizieren.
 */
export function defaultLlmsTxtInput() {
  return {
    title: LLMS_TXT_TITLE,
    description: LLMS_TXT_DESCRIPTION,
    sections: LLMS_TXT_SECTIONS,
  };
}

// ---------------------------------------------------------------------------
// CLI entry point
// ---------------------------------------------------------------------------

/**
 * Lokalisiert die Repo-Wurzel relativ zu dieser Datei. Das Skript liegt unter
 * `<repo>/website/scripts/`, die Quelldateien unter `<repo>/CONTEXT.md` und
 * `<repo>/docs/zielgruppe.md`.
 */
function repoRoot() {
  const here = dirname(fileURLToPath(import.meta.url));
  return resolve(here, "..", "..");
}

/**
 * Pfad-Konstanten als Funktion, damit Tests sie via `process.env` überschreiben
 * können — `main()` greift auf `process.env.WHISPASTE_REPO_ROOT` zurück.
 */
function paths() {
  const root = process.env.WHISPASTE_REPO_ROOT
    ? resolve(process.env.WHISPASTE_REPO_ROOT)
    : repoRoot();
  return {
    contextMd: join(root, "CONTEXT.md"),
    zielgruppeMd: join(root, "docs", "zielgruppe.md"),
    outLlmsTxt: join(root, "website", "public", "llms.txt"),
    outLlmsFullTxt: join(root, "website", "public", "llms-full.txt"),
  };
}

export async function main() {
  const p = paths();
  const [contextMd, zielgruppeMd] = await Promise.all([
    readOptional(p.contextMd),
    readOptional(p.zielgruppeMd),
  ]);

  // Quelldateien fehlen (z. B. CI-Clone ohne PROTECTED-Dateien). In diesem
  // Fall behalten wir die bereits committeten Outputs unter `website/public/`
  // bei und brechen ohne Fehler ab — der Production-Build nutzt dann den
  // letzten Maintainer-Generate-Stand.
  if (contextMd === null || zielgruppeMd === null) {
    const missing = [];
    if (contextMd === null) missing.push("CONTEXT.md");
    if (zielgruppeMd === null) missing.push("docs/zielgruppe.md");
    process.stderr.write(
      `generate-llms-txt: source file(s) missing: ${missing.join(", ")}. ` +
        `Keeping existing website/public/llms*.txt unchanged. ` +
        `(This is expected in a fresh CI clone; the maintainer regenerates and commits locally.)\n`,
    );
    return { regenerated: false, missing };
  }

  const llmsTxt = buildLlmsTxt(defaultLlmsTxtInput());
  const llmsFullTxt = buildLlmsFullTxt({
    contextSections: extractSections(contextMd, [1, 2, 3, 4]),
    zielgruppeMd,
  });

  await Promise.all([
    writeFile(p.outLlmsTxt, llmsTxt, "utf8"),
    writeFile(p.outLlmsFullTxt, llmsFullTxt, "utf8"),
  ]);

  process.stdout.write(
    `generate-llms-txt: wrote ${p.outLlmsTxt} (${llmsTxt.length} bytes) and ${p.outLlmsFullTxt} (${llmsFullTxt.length} bytes)\n`,
  );
  return { regenerated: true, bytes: { llmsTxt: llmsTxt.length, llmsFullTxt: llmsFullTxt.length } };
}

// Only auto-run when invoked as a CLI (not when imported as a module).
const invokedAsCli = (() => {
  if (!process.argv[1]) return false;
  try {
    return pathToFileURL(process.argv[1]).href === import.meta.url;
  } catch {
    return false;
  }
})();

if (invokedAsCli) {
  main().catch((err) => {
    process.stderr.write(`generate-llms-txt: ${err.message ?? err}\n`);
    process.exit(1);
  });
}
