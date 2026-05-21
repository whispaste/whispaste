#!/usr/bin/env node
/**
 * Anti-Vokabular-CI-Gate — Drift-Schutz für die Brand-Sprache.
 *
 * Liest die `antiVocabulary`-Tabelle aus `src/data/brand-glossary.ts` (Single
 * Source of Truth, siehe Slice 01 des SEO-Overhaul-Feature) und scannt zwei
 * Quellen:
 *
 *   1. Das gebaute HTML unter `website/dist/**\/*.html` plus eine explizite
 *      `.txt`-Allowlist (`llms.txt`, `llms-full.txt`, `ai.txt`).
 *   2. Die Store-Marketing-Markdown-Dateien unter `<repo-root>/store/*.md`
 *      (Issue 15 des SEO-Overhaul-Feature — sorgt dafür, dass eine Brand-
 *      Sprach-Verletzung im Microsoft-Store-Listing oder im DMG-Wording
 *      genauso auffällt wie eine auf der Website).
 *
 * Beide Quellen laufen durch dieselbe `scanHtml`-Pipeline; der Name ist
 * historisch gewachsen, die Implementierung ist text-pattern-basiert und
 * funktioniert auf HTML, Plain-Text und Markdown gleichermaßen. Kontrastive
 * Sektionen werden über die HTML-Kommentar-Marker
 * `<!-- seo-audit:contrastive -->` … `<!-- /seo-audit:contrastive -->`
 * ausgeklammert — Markdown unterstützt HTML-Kommentare verbatim, sodass die
 * Marker auch dort funktionieren. Innerhalb der Marker zählen Treffer mit
 * `contrastiveAllowed: true` nicht als Verstoß.
 *
 * Aufruf: `node scripts/check-brand-vocabulary.mjs` (typischerweise als
 * `astro build && node scripts/check-brand-vocabulary.mjs` via npm-Script
 * `build:check`). Exit-Code 0 bei sauberem Build, Exit-Code 1 bei Verstößen
 * inklusive Zitations-Liste (`file:line — term → replacement`).
 *
 * Die Kernfunktionen (`scanHtml`, `stripContrastive`, `buildTermRegex`,
 * `walkDistFiles`, `walkStoreFiles`) werden separat exportiert und vom
 * Vitest-Test unter `website/scripts/__tests__/check-brand-vocabulary.test.ts`
 * verifiziert.
 *
 * Node-Voraussetzung: ≥ 22.6 mit `--experimental-strip-types` bzw. ≥ 23, da
 * `brand-glossary.ts` direkt aus `.mjs` importiert wird (Native TS-Strip in
 * Node).
 */

import { readFile, readdir, stat } from "node:fs/promises";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

import { antiVocabulary } from "../src/data/brand-glossary.ts";

// ---------------------------------------------------------------------------
// Pure helpers (testable in isolation)
// ---------------------------------------------------------------------------

/**
 * Kontrastive Marker-Paare, mit denen explizite Vergleichs-Sektionen aus dem
 * Scan ausgeklammert werden. Format ist bewusst HTML-Kommentar, damit die
 * Marker im gerenderten HTML stehen, im Browser aber unsichtbar bleiben.
 */
export const CONTRASTIVE_OPEN = "<!-- seo-audit:contrastive -->";
export const CONTRASTIVE_CLOSE = "<!-- /seo-audit:contrastive -->";

/**
 * Entfernt alle Inhalte zwischen `CONTRASTIVE_OPEN` und `CONTRASTIVE_CLOSE`
 * aus der HTML-Eingabe und ersetzt sie durch Leerzeilen, damit die
 * Zeilennummerierung für nachfolgende Treffer stabil bleibt. Mehrere Marker-
 * Paare werden unabhängig voneinander behandelt; ein nicht geschlossenes
 * Open-Tag entfernt den Rest des Strings.
 *
 * @param {string} html - Roh-HTML.
 * @returns {string} HTML mit gestrippten kontrastiven Sektionen.
 */
export function stripContrastive(html) {
  if (!html.includes(CONTRASTIVE_OPEN)) return html;
  let out = "";
  let cursor = 0;
  while (cursor < html.length) {
    const openIdx = html.indexOf(CONTRASTIVE_OPEN, cursor);
    if (openIdx === -1) {
      out += html.slice(cursor);
      break;
    }
    out += html.slice(cursor, openIdx);
    const closeIdx = html.indexOf(
      CONTRASTIVE_CLOSE,
      openIdx + CONTRASTIVE_OPEN.length,
    );
    if (closeIdx === -1) {
      // Unclosed marker — drop the rest, but preserve newline count so line
      // numbers remain meaningful in the citation output.
      const dropped = html.slice(openIdx);
      out += "\n".repeat(countNewlines(dropped));
      break;
    }
    const dropped = html.slice(openIdx, closeIdx + CONTRASTIVE_CLOSE.length);
    out += "\n".repeat(countNewlines(dropped));
    cursor = closeIdx + CONTRASTIVE_CLOSE.length;
  }
  return out;
}

function countNewlines(str) {
  let n = 0;
  for (let i = 0; i < str.length; i++) if (str.charCodeAt(i) === 10) n++;
  return n;
}

/**
 * Baut die Such-Regex für einen Anti-Vokabular-Begriff. Englische Wörter
 * (ASCII-only) bekommen Wort-Grenzen (`\b`), damit Substring-Treffer wie
 * `predication` bei Suche nach `dictation` nicht fälschlich matchen. Begriffe
 * mit Nicht-ASCII-Zeichen (z. B. `Sprach-Übersetzer`) oder Bindestrich-
 * Konstrukten (`Diktier-Tool`) verzichten auf `\b`, weil `\b` in JS-Regex
 * nur an ASCII-Wortgrenzen feuert und sonst falsch oder gar nicht matcht.
 * Alle Matches sind case-insensitiv (`/i`).
 *
 * @param {string} term - Anti-Vokabular-Begriff.
 * @returns {RegExp} globale, case-insensitive Such-Regex.
 */
export function buildTermRegex(term) {
  const escaped = term.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const isAsciiWord = /^[A-Za-z]+$/.test(term);
  const pattern = isAsciiWord ? `\\b${escaped}\\b` : escaped;
  return new RegExp(pattern, "gi");
}

/**
 * Findet alle Verstöße in einem HTML-String. Kontrastive Sektionen werden
 * vorab entfernt; Begriffe mit `contrastiveAllowed: true` bleiben dadurch
 * straflos. Reihenfolge der Findings: per Datei nach Zeile, dann nach Term-
 * Reihenfolge aus dem Glossar.
 *
 * @param {string} html - Roh-HTML einer Page.
 * @param {ReadonlyArray<{ term: string, replacement: string, rationale: string, contrastiveAllowed?: boolean }>} vocabulary -
 *   Anti-Vokabular-Tabelle.
 * @returns {Array<{ line: number, column: number, term: string, match: string, replacement: string, rationale: string }>}
 */
export function scanHtml(html, vocabulary) {
  const stripped = stripContrastive(html);
  const lineStarts = computeLineStarts(stripped);
  const findings = [];
  for (const entry of vocabulary) {
    const regex = buildTermRegex(entry.term);
    let m;
    while ((m = regex.exec(stripped)) !== null) {
      const { line, column } = offsetToLineCol(m.index, lineStarts);
      findings.push({
        line,
        column,
        term: entry.term,
        match: m[0],
        replacement: entry.replacement,
        rationale: entry.rationale,
      });
      if (m.index === regex.lastIndex) regex.lastIndex++;
    }
  }
  findings.sort((a, b) =>
    a.line !== b.line ? a.line - b.line : a.column - b.column,
  );
  return findings;
}

function computeLineStarts(str) {
  const starts = [0];
  for (let i = 0; i < str.length; i++) {
    if (str.charCodeAt(i) === 10) starts.push(i + 1);
  }
  return starts;
}

function offsetToLineCol(offset, lineStarts) {
  // Binary search for the largest line-start ≤ offset.
  let lo = 0;
  let hi = lineStarts.length - 1;
  while (lo < hi) {
    const mid = (lo + hi + 1) >>> 1;
    if (lineStarts[mid] <= offset) lo = mid;
    else hi = mid - 1;
  }
  return { line: lo + 1, column: offset - lineStarts[lo] + 1 };
}

/**
 * Rekursive Verzeichnis-Traversierung; liefert alle Dateipfade unter `root`,
 * die auf `.html` enden — plus eine explizite Allowlist von `.txt`-Outputs,
 * die ebenfalls Brand-Sprach-kritisch sind (`llms.txt`, `llms-full.txt` —
 * siehe Issue 05 / PRD §D, LLM-Search-Foundation). `.txt` wird bewusst NICHT
 * generisch über die Extension gematcht, damit andere Text-Assets unter
 * `dist/` (z. B. `robots.txt` mit Sitemap-URL, oder zukünftige IndexNow-Key-
 * Files) nicht versehentlich gescannt werden.
 *
 * @param {string} root - Absoluter Pfad zum Build-Output (typischerweise
 *   `<repo>/website/dist`).
 * @returns {Promise<string[]>} sortierte absolute Pfade.
 */
export async function walkDistFiles(root) {
  const out = [];
  await walk(root, out);
  // Explizite Allowlist für `.txt`-Outputs, die Brand-Vocabulary-konform
  // sein müssen. Reihenfolge: existierende Files anhängen, fehlende stumm
  // übergehen (z. B. wenn der Generator vor dem ersten Maintainer-Lauf noch
  // keine Outputs geschrieben hat).
  for (const name of TXT_ALLOWLIST) {
    const p = join(root, name);
    const st = await stat(p).catch(() => null);
    if (st && st.isFile()) out.push(p);
  }
  out.sort();
  return out;
}

/**
 * `.txt`-Outputs unter `dist/`, die genauso wie HTML auf Brand-Vokabular
 * geprüft werden. Erweiterungen müssen hier explizit eingetragen werden.
 *
 * `robots.txt` ist bewusst NICHT enthalten: Inhalt ist primär Crawler-Syntax
 * (User-agent / Allow / Sitemap), kein Marketing-Text. `ai.txt` (Issue 08)
 * spiegelt die AI-Crawler-Policy und wird gescannt, weil es zusätzlich
 * Lizenz-/Kontakt-Felder enthält, die Brand-konform bleiben müssen.
 */
export const TXT_ALLOWLIST = Object.freeze([
  "llms.txt",
  "llms-full.txt",
  "ai.txt",
]);

async function walk(dir, acc) {
  let entries;
  try {
    entries = await readdir(dir, { withFileTypes: true });
  } catch (err) {
    if (err && /** @type {NodeJS.ErrnoException} */ (err).code === "ENOENT") {
      return;
    }
    throw err;
  }
  for (const ent of entries) {
    const p = join(dir, ent.name);
    if (ent.isDirectory()) {
      await walk(p, acc);
    } else if (ent.isFile() && p.endsWith(".html")) {
      acc.push(p);
    }
  }
}

/**
 * Sammelt alle Top-Level-Markdown-Dateien unter `<repo-root>/store/` (Issue
 * 15 des SEO-Overhaul-Feature). Nur Top-Level (`store/*.md`) — Unterordner
 * wie `store/de-DE/` enthalten Partner-Center-Plain-Text-Snippets, die
 * separat über `description.txt` / `features.txt` gepflegt werden und nicht
 * Teil dieses Markdown-Scans sind. Falls das `store/`-Verzeichnis nicht
 * existiert, liefert die Funktion eine leere Liste ohne Fehler — der Scan
 * bleibt damit auch in Sandbox-Setups grün, in denen `store/` ausgelassen
 * wurde.
 *
 * @param {string} storeDir - Absoluter Pfad zum `store`-Verzeichnis.
 * @returns {Promise<string[]>} sortierte absolute Pfade aller `store/*.md`.
 */
export async function walkStoreFiles(storeDir) {
  let entries;
  try {
    entries = await readdir(storeDir, { withFileTypes: true });
  } catch (err) {
    if (err && /** @type {NodeJS.ErrnoException} */ (err).code === "ENOENT") {
      return [];
    }
    throw err;
  }
  const out = [];
  for (const ent of entries) {
    if (ent.isFile() && ent.name.endsWith(".md")) {
      out.push(join(storeDir, ent.name));
    }
  }
  out.sort();
  return out;
}

// ---------------------------------------------------------------------------
// CLI entry point
// ---------------------------------------------------------------------------

/**
 * Hauptlauf: scannt sowohl den Website-Build-Output (`dist/**\/*.html` plus
 * `.txt`-Allowlist) als auch die Store-Marketing-Markdown-Quellen
 * (`<repo-root>/store/*.md`, siehe Issue 15) und liefert ein Aggregat-Objekt
 * mit allen Verstößen pro Datei. Exit-Code-Mapping erfolgt im CLI-Wrapper,
 * damit `runCheck` auch in Tests konsumierbar bleibt.
 *
 * Die einzelnen Quell-Listen werden zusätzlich zurückgegeben (`htmlCount`,
 * `txtCount`, `markdownCount`), damit `formatReport` eine aussagekräftige
 * Summary-Zeile bauen kann.
 *
 * @param {object} opts
 * @param {string} opts.distDir - absoluter Pfad zum `dist`-Verzeichnis.
 * @param {string} [opts.storeDir] - optionaler absoluter Pfad zum
 *   `store`-Verzeichnis (Default: weggelassen → keine Store-Scan-Phase).
 * @param {ReadonlyArray<{ term: string, replacement: string, rationale: string, contrastiveAllowed?: boolean }>} opts.vocabulary
 * @returns {Promise<{
 *   totalFiles: number,
 *   totalViolations: number,
 *   htmlCount: number,
 *   txtCount: number,
 *   markdownCount: number,
 *   files: Array<{ file: string, violations: ReturnType<typeof scanHtml> }>
 * }>}
 */
export async function runCheck({ distDir, storeDir, vocabulary }) {
  const distStat = await stat(distDir).catch(() => null);
  if (!distStat || !distStat.isDirectory()) {
    throw new Error(
      `dist directory not found at ${distDir}. Run \`npm run build\` first or set BRAND_DIST_DIR.`,
    );
  }
  const distFiles = await walkDistFiles(distDir);
  const storeFiles = storeDir ? await walkStoreFiles(storeDir) : [];

  // Zählung pro Quellklasse für die Summary-Zeile.
  let htmlCount = 0;
  let txtCount = 0;
  for (const f of distFiles) {
    if (f.endsWith(".html")) htmlCount++;
    else if (f.endsWith(".txt")) txtCount++;
  }
  const markdownCount = storeFiles.length;

  const perFile = [];
  let totalViolations = 0;
  for (const f of [...distFiles, ...storeFiles]) {
    const text = await readFile(f, "utf8");
    const violations = scanHtml(text, vocabulary);
    if (violations.length > 0) {
      perFile.push({ file: f, violations });
      totalViolations += violations.length;
    }
  }
  return {
    totalFiles: distFiles.length + storeFiles.length,
    totalViolations,
    htmlCount,
    txtCount,
    markdownCount,
    files: perFile,
  };
}

/**
 * Formatiert das `runCheck`-Ergebnis als menschenlesbaren Report. Wird vom
 * CLI-Wrapper auf stderr geschrieben, bleibt aber separat testbar.
 *
 * Die Summary-Zeile listet die drei gescannten Quellklassen einzeln auf
 * (HTML aus `dist/`, TXT-Allowlist aus `dist/`, Markdown aus `store/`),
 * damit ein „0 Verstöße in N HTML + M TXT + K Markdown"-Lauf auf einen
 * Blick zeigt, dass alle drei Pfade gescannt wurden.
 */
export function formatReport(result, { distDir }) {
  const lines = [];
  const scopeSummary = formatScopeSummary(result);
  if (result.totalViolations === 0) {
    lines.push(
      `✓ Brand-Vokabular-Check: 0 Verstöße in ${scopeSummary} unter ${distDir}.`,
    );
    return lines.join("\n");
  }
  lines.push(
    `✗ Brand-Vokabular-Check: ${result.totalViolations} Verstöße in ${result.files.length} von ${scopeSummary}.`,
  );
  for (const { file, violations } of result.files) {
    const rel = relative(process.cwd(), file);
    lines.push("");
    lines.push(`  ${rel}`);
    for (const v of violations) {
      const replacementText =
        v.replacement.length > 0 ? `→ "${v.replacement}"` : "(streichen)";
      lines.push(
        `    ${rel}:${v.line}:${v.column}  "${v.match}" ${replacementText}  — ${v.rationale}`,
      );
    }
  }
  lines.push("");
  lines.push(
    `Tipp: kontrastive Vergleichs-Sektionen mit ${CONTRASTIVE_OPEN} … ${CONTRASTIVE_CLOSE} markieren.`,
  );
  return lines.join("\n");
}

/**
 * Baut die "N HTML + M TXT + K Markdown-Datei(en)"-Phrase für die Summary-
 * Zeile. Klassen mit Count = 0 werden weggelassen; bleibt nur die Gesamt-
 * Datei-Zahl übrig, fällt der Report auf die alte Pluralform zurück, damit
 * der Output bei reiner HTML-Erstaufrüstung nicht künstlich aufgebläht wird.
 */
function formatScopeSummary(result) {
  const parts = [];
  if (result.htmlCount > 0) parts.push(`${result.htmlCount} HTML`);
  if (result.txtCount > 0) parts.push(`${result.txtCount} TXT`);
  if (result.markdownCount > 0) parts.push(`${result.markdownCount} Markdown`);
  if (parts.length === 0) {
    return `${result.totalFiles} Datei(en)`;
  }
  return `${parts.join(" + ")}-Datei(en)`;
}

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

async function main() {
  const distDir = resolve(
    process.env.BRAND_DIST_DIR ?? join(__dirname, "..", "dist"),
  );
  // Repo-Root liegt eine Ebene über `website/` — `store/` ist eine Top-Level-
  // Schwester von `website/`. Override via `BRAND_STORE_DIR` für Tests und
  // Sandbox-Setups.
  const storeDir = resolve(
    process.env.BRAND_STORE_DIR ?? join(__dirname, "..", "..", "store"),
  );
  const result = await runCheck({
    distDir,
    storeDir,
    vocabulary: antiVocabulary,
  });
  const report = formatReport(result, { distDir });
  if (result.totalViolations === 0) {
    process.stdout.write(report + "\n");
    process.exit(0);
  }
  process.stderr.write(report + "\n");
  process.exit(1);
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
    process.stderr.write(`check-brand-vocabulary: ${err.message ?? err}\n`);
    process.exit(2);
  });
}
