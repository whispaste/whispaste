#!/usr/bin/env node
/**
 * apply-store-metadata.mjs
 *
 * Merges WhisPaste's centrally-managed Store metadata (price + listing text,
 * both versioned under store/) into a Microsoft Store submission JSON, as
 * returned by `msstore submission get <productId>`.
 *
 * WHY THIS EXISTS
 *   `msstore submission updateMetadata <productId> <json>` takes the FULL
 *   submission object, not a partial patch — so every field we don't
 *   explicitly manage (Images, ApplicationPackages, hardware requirements,
 *   …) must be read from the live submission and passed straight through
 *   unchanged. This script does exactly that: read the current submission,
 *   overlay our managed fields on top, emit the merged result.
 *
 * TWO PROBLEMS THIS SCRIPT SOLVES THAT THE RAW CLI OUTPUT DOESN'T:
 *   1. `msstore submission get` line-wraps long string values for terminal
 *      display using RAW, un-escaped newlines — which is not valid JSON.
 *      This script repairs that (walks the text char-by-char, replacing a
 *      raw newline with a space, but ONLY while inside a JSON string
 *      literal) before parsing. See ~/.claude/infrastructure/
 *      microsoft-partner-center.md §6 for the full story.
 *   2. The CLI also prints ANSI color codes and banner text before the
 *      actual `{...}` body — stripped here too.
 *
 * MANAGED FIELDS (everything else in the submission passes through as-is)
 *   Listings.<locale>.BaseListing.Title               ← store/defaults.json "default.Title"
 *   (NOT Pricing — WhisPaste's account is on Pricing V2 / Advanced Pricing
 *   Model, for which Microsoft's own docs say the Submission API can't be
 *   used to write pricing at all; see the comment on mergeManagedMetadata.)
 *   Listings.<locale>.BaseListing.Description          ← store/<folder>/description.txt
 *   Listings.<locale>.BaseListing.Features              ← store/<folder>/features.txt (one per line)
 *   Listings.<locale>.BaseListing.Keywords              ← store/<folder>/search-terms.txt (one per line)
 *   Listings.<locale>.BaseListing.ReleaseNotes          ← store/<folder>/release-notes.txt
 *
 * USAGE
 *   msstore submission get <productId> | node scripts/apply-store-metadata.mjs > merged.json
 *   node scripts/apply-store-metadata.mjs --in raw-cli-output.txt --out merged.json
 *   node scripts/apply-store-metadata.mjs --in raw.txt --check   # validate only, print summary
 *
 * Requires Node 18+. No dependencies. Windows/pwsh-friendly (plain stdio).
 */

import { readFileSync, writeFileSync } from 'fs';
import { resolve, join } from 'path';
import { fileURLToPath, pathToFileURL } from 'url';
import { dirname } from 'path';

const __dir = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(__dir, '../');

// ── Step 1: repair the CLI's line-wrapped pseudo-JSON into real JSON ────────

/**
 * Strips ANSI escape codes + any CLI banner text before the first `{`, then
 * walks the remainder char-by-char: while inside a JSON string literal, a
 * raw newline/carriage-return (the CLI's own word-wrapping, not an escaped
 * `\n`) is replaced with a single space instead of left as an invalid
 * control character.
 */
export function repairMsstoreJson(rawText) {
  const noAnsi = rawText.replace(/\x1b\[[0-9;]*m/g, '');
  const start = noAnsi.indexOf('{');
  if (start === -1) {
    throw new Error('No JSON object found in input (missing "{").');
  }
  const body = noAnsi.slice(start);

  let out = '';
  let inString = false;
  let escape = false;
  for (const ch of body) {
    if (inString) {
      if (escape) {
        out += ch;
        escape = false;
      } else if (ch === '\\') {
        out += ch;
        escape = true;
      } else if (ch === '"') {
        out += ch;
        inString = false;
      } else if (ch === '\n' || ch === '\r') {
        out += ' ';
      } else {
        out += ch;
      }
    } else {
      if (ch === '"') inString = true;
      out += ch;
    }
  }
  return out;
}

// ── Step 2: read our managed source-of-truth files ──────────────────────────

function readTrim(path) {
  return readFileSync(path, 'utf8').replace(/\r\n/g, '\n').trim();
}

function readList(path) {
  return readTrim(path)
    .split('\n')
    .map((l) => l.trim())
    .filter((l) => l !== '');
}

/**
 * Loads store/defaults.json + the per-locale text files and returns the
 * overlay to apply on top of a fetched submission JSON. `locales` maps
 * store/ folder name ("en-US") to the msstore submission's locale key
 * ("en-us") — these differ in case/format, unlike the CSV generator's
 * columns, which is why this is kept separate from generate-store-listing.mjs
 * rather than shared wholesale.
 */
export function loadManagedMetadata(storeDir) {
  const defaults = JSON.parse(readFileSync(join(storeDir, 'defaults.json'), 'utf8'));
  const title = defaults.default?.Title;
  if (!title) {
    throw new Error('store/defaults.json is missing "default.Title".');
  }

  // store/ folder name → msstore submission locale key (lowercase, en-US → en-us).
  const localeMap = { 'en-US': 'en-us', 'de-DE': 'de' };

  const listings = {};
  for (const [folder, submissionLocale] of Object.entries(localeMap)) {
    const dir = join(storeDir, folder);
    listings[submissionLocale] = {
      Title: title,
      Description: readTrim(join(dir, 'description.txt')),
      Features: readList(join(dir, 'features.txt')),
      Keywords: readList(join(dir, 'search-terms.txt')),
      ReleaseNotes: readTrim(join(dir, 'release-notes.txt')),
    };
  }

  return { listings };
}

// ── Step 3: merge managed fields into the fetched submission, leave the rest untouched ──

export function mergeManagedMetadata(submission, managed) {
  const merged = structuredClone(submission);

  // Pricing is deliberately NOT touched here. Microsoft's own docs are
  // explicit: "You can't use this API with apps or add-ons that are on
  // Pricing Version 2" (Create and manage submissions, learn.microsoft.com)
  // — WhisPaste's account is on Pricing V2 ("Advanced Pricing Model"),
  // where `isAdvancedPricingModel` is read-only and every attempt to write
  // Pricing.PriceId fails submission commit with "Price Tier is not
  // supported", regardless of which tier string is sent. There is no
  // documented alternative schema and no public Tier1012–Tier1424→price
  // mapping (2026-07-21 incident: every real commit attempt failed on this
  // exact field until it was removed from the managed set). Price is set
  // once, manually, in Partner Center → Pricing and availability — the only
  // Microsoft-sanctioned path for a Pricing V2 account — and this script
  // now leaves whatever value is already there untouched, same as every
  // other field it doesn't manage.

  for (const [locale, fields] of Object.entries(managed.listings)) {
    if (!merged.Listings[locale]) {
      throw new Error(
        `Submission has no "${locale}" listing to merge into — expected locales: ${Object.keys(merged.Listings).join(', ')}`,
      );
    }
    merged.Listings[locale].BaseListing = {
      ...merged.Listings[locale].BaseListing,
      ...fields,
    };
  }

  return merged;
}

// ── CLI entry point ──────────────────────────────────────────────────────────

function parseArgs(argv) {
  const out = { in: null, out: null, storeDir: 'store', check: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--in') out.in = argv[++i];
    else if (a === '--out') out.out = argv[++i];
    else if (a === '--store-dir') out.storeDir = argv[++i];
    else if (a === '--check') out.check = true;
    else if (a === '-h' || a === '--help') {
      process.stdout.write(
        'Usage: apply-store-metadata.mjs [--in raw.txt] [--out merged.json] [--store-dir store] [--check]\n' +
          '  Reads raw `msstore submission get` output from --in, or stdin if omitted.\n',
      );
      process.exit(0);
    }
  }
  return out;
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const raw = args.in
    ? readFileSync(resolve(process.cwd(), args.in), 'utf8')
    : readFileSync(0, 'utf8'); // stdin

  const repaired = repairMsstoreJson(raw);
  let submission;
  try {
    submission = JSON.parse(repaired);
  } catch (e) {
    process.stderr.write(`✗ Could not parse submission JSON even after repair: ${e.message}\n`);
    process.exit(1);
  }

  const storeDir = resolve(repoRoot, args.storeDir);
  const managed = loadManagedMetadata(storeDir);
  const merged = mergeManagedMetadata(submission, managed);

  process.stderr.write(
    `Merged: locales=[${Object.keys(managed.listings).join(', ')}] (Pricing left untouched — Pricing V2 account)\n`,
  );

  if (args.check) {
    process.stderr.write('--check: validation only, nothing written.\n');
    return;
  }

  const json = JSON.stringify(merged);
  if (args.out) {
    writeFileSync(resolve(process.cwd(), args.out), json, 'utf8');
    process.stderr.write(`Wrote ${args.out}\n`);
  } else {
    process.stdout.write(json);
  }
}

// pathToFileURL() (not a manual `file://${argv[1]}` concat) is required for
// this "am I the entry module" check to work on Windows — argv[1] there is a
// backslash path with no scheme (`D:\a\whispaste\...`), which never equals
// import.meta.url's `file:///D:/a/whispaste/...` form. The msstore-CLI job
// runs on windows-latest, where the naive concat silently never calls main()
// — no error, no output, exit 0 — and the failure only surfaces one step
// later when the never-written output file is missing (2026-07-21 incident).
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main();
}
