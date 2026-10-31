#!/usr/bin/env node
/**
 * generate-store-listing.mjs
 *
 * Builds a Microsoft Store "Import listings" CSV from the human-readable
 * source files under store/. Runs entirely locally — no network, no GitHub
 * Action, no Partner Center API call. The output CSV is uploaded by hand via
 * Partner Center → "Import listings".
 *
 * WHY A COMPACT CSV
 *   Per MS docs, an import CSV may contain ONLY the rows you intend to edit
 *   (everything else — screenshots, logos, trailers, captions, hardware reqs —
 *   stays untouched in Partner Center). So we emit just the text fields we
 *   manage, which keeps the file small, diff-able, and free of internal
 *   submission/asset IDs.
 *
 * SOURCE MODEL (store/)
 *   store/defaults.json
 *       "locales": { "<folder>": "<csv-column>" }   e.g. "en-US": "en-us", "de-DE": "de"
 *       "default": { "<FieldName>": "<value>" }      sprachneutral → default column
 *   store/<locale>/description.txt        → Description
 *   store/<locale>/short-description.txt  → ShortDescription
 *   store/<locale>/release-notes.txt      → ReleaseNotes ("What's new")
 *   store/<locale>/copyright.txt          → CopyrightTrademarkInformation
 *   store/<locale>/license-terms.txt      → AdditionalLicenseTerms
 *   store/<locale>/features.txt           → Feature1..FeatureN  (one bullet per line)
 *   store/<locale>/search-terms.txt       → SearchTerm1..SearchTermN (one term per line)
 *   store/<locale>/short-title.txt        → ShortTitle        (optional)
 *   store/<locale>/sort-title.txt         → SortTitle         (optional)
 *   store/<locale>/minimum-hardware.txt   → MinimumHardwareReq1..N   (optional)
 *   store/<locale>/recommended-hardware.txt → RecommendedHardwareReq1..N (optional)
 *
 *   Missing optional files are skipped silently; a missing required file is an
 *   error (exit 1) so a half-empty listing never ships by accident.
 *
 * FIELD IDS ARE FROZEN
 *   The (Field, ID, Type) triples are part of the Partner Center contract and
 *   must never be edited. They are hard-coded below, derived from the official
 *   export. Changing them breaks the import.
 *
 * USAGE
 *   node scripts/generate-store-listing.mjs                  # → store/_build/listing-import.csv
 *   node scripts/generate-store-listing.mjs --check          # validate only, write nothing
 *   node scripts/generate-store-listing.mjs --out foo.csv    # custom output path
 *   node scripts/generate-store-listing.mjs --store-dir store
 *
 * Requires Node 18+. No dependencies.
 */

import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'fs';
import { resolve, dirname, join } from 'path';
import { fileURLToPath } from 'url';

const __dir = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(__dir, '../');

// ── Frozen field contract (Field, ID, Type) — do NOT edit IDs ────────────────

const SCALAR_FIELDS = [
  { field: 'Description', id: 2, slug: 'description', required: true },
  { field: 'ReleaseNotes', id: 3, slug: 'release-notes', required: false },
  { field: 'ShortDescription', id: 8, slug: 'short-description', required: true },
  { field: 'CopyrightTrademarkInformation', id: 12, slug: 'copyright', required: false },
  { field: 'AdditionalLicenseTerms', id: 13, slug: 'license-terms', required: false },
];

const OPTIONAL_SCALAR_FIELDS = [
  { field: 'ShortTitle', id: 5, slug: 'short-title' },
  { field: 'SortTitle', id: 6, slug: 'sort-title' },
];

// Sprachneutral: value comes from defaults.json "default" map, goes to default column.
const DEFAULT_FIELDS = [
  { field: 'Title', id: 4, key: 'Title' },
  { field: 'VoiceTitle', id: 7, key: 'VoiceTitle' },
  { field: 'DevStudio', id: 9, key: 'DevStudio' },
];

// Repeatable fields: <prefix><N> with sequential IDs.
const LIST_FIELDS = [
  { prefix: 'Feature', baseId: 700, max: 20, slug: 'features', perItemLimit: 200, required: true },
  { prefix: 'SearchTerm', baseId: 900, max: 7, slug: 'search-terms', perItemLimit: null, required: true },
  { prefix: 'MinimumHardwareReq', baseId: 800, max: 11, slug: 'minimum-hardware', perItemLimit: 200, required: false },
  { prefix: 'RecommendedHardwareReq', baseId: 850, max: 11, slug: 'recommended-hardware', perItemLimit: 200, required: false },
];

// Documented length limits (add-and-edit-store-listing-info). Only fields with
// an official limit are validated; unknowns are left alone to avoid false noise.
const LIMITS = {
  Description: { hard: 10000 },
  ReleaseNotes: { hard: 1500 },
  ShortTitle: { hard: 50 },
  SortTitle: { hard: 255 },
  VoiceTitle: { hard: 255 },
  ShortDescription: { hard: 1000, soft: 270 },
};

// ── CSV writer (RFC 4180, CRLF, always-quoted value cells, UTF-8 no BOM) ─────

function csvCell(raw, { quote = true } = {}) {
  const s = raw == null ? '' : String(raw);
  if (!quote) return s;
  return '"' + s.replace(/"/g, '""') + '"';
}

function csvRow(cells) {
  return cells.map((c) => csvCell(c)).join(',') + '\r\n';
}

// ── Helpers ──────────────────────────────────────────────────────────────────

function readTrim(path) {
  return readFileSync(path, 'utf8').replace(/\r\n/g, '\n').trim();
}

function readList(path) {
  return readTrim(path)
    .split('\n')
    .map((l) => l.trim())
    .filter((l) => l !== '');
}

function readOrNull(path) {
  if (!existsSync(path)) return null;
  return readTrim(path);
}

function readListOrNull(path) {
  if (!existsSync(path)) return null;
  return readList(path);
}

function parseArgs(argv) {
  const out = { storeDir: 'store', out: null, check: false, template: null };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--store-dir') out.storeDir = argv[++i];
    else if (a === '--out') out.out = argv[++i];
    else if (a === '--template') out.template = argv[++i];
    else if (a === '--check' || a === '--dry-run') out.check = true;
    else if (a === '-h' || a === '--help') {
      process.stdout.write(
        'Usage: generate-store-listing.mjs [--store-dir store] [--out file.csv] ' +
          '[--template export.csv] [--check]\n',
      );
      process.exit(0);
    }
  }
  return out;
}

// ── Build ────────────────────────────────────────────────────────────────────

function build({ storeDir, template }) {
  const storePath = resolve(repoRoot, storeDir);
  const defaultsPath = join(storePath, 'defaults.json');
  if (!existsSync(defaultsPath)) {
    throw new Error(`Missing ${defaultsPath}. Create store/defaults.json with locales + default.`);
  }
  const defaults = JSON.parse(readFileSync(defaultsPath, 'utf8'));
  const locales = defaults.locales;
  if (!locales || Object.keys(locales).length === 0) {
    throw new Error('store/defaults.json "locales" is empty or missing.');
  }
  const localeCols = Object.values(locales); // insertion order → CSV column order
  const defaultMap = defaults.default || {};

  // Optional --template: take the header row verbatim from a fresh Partner Center
  // export so the Type column (e.g. localized "Type (Typ)") and locale codes match
  // exactly what Partner Center expects. MS docs: "Don't change Field/ID/Type" —
  // borrowing the header byte-for-byte is the safest way to honour that.
  let templateHeaderRaw = null;
  if (template) {
    if (!existsSync(template)) {
      throw new Error(`Template not found: ${template}`);
    }
    const tplRaw = readFileSync(template, 'utf8');
    const firstLine = tplRaw.split(/\r?\n/, 1)[0];
    const tplCols = firstLine.split(',').map((c) => c.replace(/^"|"$/g, '').replace(/""/g, '"'));
    if (tplCols.length < 4) {
      throw new Error(`Template header has < 4 columns: ${firstLine}`);
    }
    const tplLocales = tplCols.slice(4);
    for (const [folder, col] of Object.entries(locales)) {
      if (!tplLocales.includes(col)) {
        throw new Error(
          `Template header missing locale column '${col}' (folder ${folder}). ` +
            `Template locales: [${tplLocales.join(', ')}]`,
        );
      }
    }
    templateHeaderRaw = firstLine;
  }

  const dataRows = [];
  const warnings = [];

  function warn(field, locale, msg) {
    warnings.push(`[${field}${locale ? ' / ' + locale : ''}] ${msg}`);
  }

  function checkLimits(field, value, locale) {
    const lim = LIMITS[field];
    if (!lim) return;
    if (lim.hard != null && value.length > lim.hard) {
      warn(field, locale, `${value.length} chars exceeds hard limit ${lim.hard}.`);
    } else if (lim.soft != null && value.length > lim.soft) {
      warn(field, locale, `${value.length} chars (recommended ≤ ${lim.soft}).`);
    }
  }

  // 1) Sprachneutral fields → default column only.
  for (const f of DEFAULT_FIELDS) {
    const val = defaultMap[f.key];
    if (!val) continue;
    checkLimits(f.field, val, null);
    const localeEmpties = localeCols.map(() => '');
      dataRows.push([f.field, String(f.id), 'Text', val, ...localeEmpties]);
  }

  // 2) Per-locale scalar fields (required + optional).
  for (const f of [...SCALAR_FIELDS, ...OPTIONAL_SCALAR_FIELDS]) {
    const localeVals = {};
    let any = false;
    for (const [folder, col] of Object.entries(locales)) {
      const val = readOrNull(join(storePath, folder, `${f.slug}.txt`));
      if (val !== null) {
        localeVals[col] = val;
        any = true;
        checkLimits(f.field, val, col);
      } else if (f.required) {
        throw new Error(`Required file missing: store/${folder}/${f.slug}.txt`);
      }
    }
    if (!any) continue;
    const cells = localeCols.map((c) => localeVals[c] ?? '');
    dataRows.push([f.field, String(f.id), 'Text', '', ...cells]);
  }

  // 3) Repeatable list fields.
  for (const lf of LIST_FIELDS) {
    const perLocale = {};
    let maxLen = 0;
    for (const [folder, col] of Object.entries(locales)) {
      const lines = readListOrNull(join(storePath, folder, `${lf.slug}.txt`));
      if (lines === null) {
        if (lf.required) {
          throw new Error(`Required file missing: store/${folder}/${lf.slug}.txt`);
        }
        continue;
      }
      if (lines.length > lf.max) {
        warn(lf.prefix, col, `${lines.length} entries exceed max ${lf.max} — extras dropped.`);
      }
      perLocale[col] = lines.slice(0, lf.max);
      maxLen = Math.max(maxLen, perLocale[col].length);
    }
    for (let i = 0; i < maxLen; i++) {
      const cells = localeCols.map((c) => {
        const v = perLocale[c]?.[i] ?? '';
        if (v && lf.perItemLimit && v.length > lf.perItemLimit) {
          warn(`${lf.prefix}${i + 1}`, c, `${v.length} chars exceeds ${lf.perItemLimit}.`);
        }
        return v;
      });
      if (!cells.some((c) => c !== '')) continue;
      dataRows.push([`${lf.prefix}${i + 1}`, String(lf.baseId + i), 'Text', '', ...cells]);
    }
  }

  // Header: byte-for-byte from the template if provided, otherwise the clean
  // default header (matches MS docs' English illustration). Value rows are
  // always RFC-4180 quoted.
  const headerCells = ['Field', 'ID', 'Type', 'default', ...localeCols];
  const headerLine = (templateHeaderRaw ?? headerCells.join(',')) + '\r\n';
  const csv = headerLine + dataRows.map(csvRow).join('');
  return { csv, warnings, localeCols, rowCount: dataRows.length, usedTemplate: !!template };
}

// ── Main ─────────────────────────────────────────────────────────────────────

function main() {
  const args = parseArgs(process.argv.slice(2));
  let result;
  try {
    result = build({ storeDir: args.storeDir, template: args.template });
  } catch (e) {
    process.stderr.write(`✗ ${e.message}\n`);
    process.exit(1);
  }

  const { csv, warnings, localeCols, rowCount } = result;

  process.stderr.write(
    `Built listing CSV: ${rowCount} field rows, locales [${localeCols.join(', ')}]` +
      `${result.usedTemplate ? ' (header from template)' : ''}.\n`,
  );
  if (warnings.length > 0) {
    process.stderr.write(`\nWarnings (${warnings.length}):\n`);
    for (const w of warnings) process.stderr.write(`  • ${w}\n`);
  } else {
    process.stderr.write('No length-limit warnings.\n');
  }

  if (args.check) {
    process.stderr.write('\n--check: validation only, nothing written.\n');
    process.exit(warnings.length > 0 ? 0 : 0);
  }

  const outPath = args.out
    ? resolve(process.cwd(), args.out)
    : join(resolve(repoRoot, args.storeDir), '_build', 'listing-import.csv');
  mkdirSync(dirname(outPath), { recursive: true });
  writeFileSync(outPath, csv, 'utf8');
  process.stderr.write(`\nWrote ${outPath}\n`);
  process.stderr.write('Import via Partner Center → app overview → "Import listings" → Import .csv.\n');
}

main();
