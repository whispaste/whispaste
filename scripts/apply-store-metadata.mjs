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
 *   Pricing.PriceId / Pricing.IsAdvancedPricingModel  ← store/defaults.json "pricing"
 *   Listings.<locale>.BaseListing.Title               ← store/defaults.json "default.Title"
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
import { fileURLToPath } from 'url';
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
  const pricing = defaults.pricing;
  if (!pricing || !pricing.priceId) {
    throw new Error('store/defaults.json is missing a "pricing.priceId" value.');
  }
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

  return {
    pricing: {
      PriceId: pricing.priceId,
      IsAdvancedPricingModel: pricing.isAdvancedPricingModel ?? false,
    },
    listings,
  };
}

// ── Step 3: merge managed fields into the fetched submission, leave the rest untouched ──

export function mergeManagedMetadata(submission, managed) {
  const merged = structuredClone(submission);

  merged.Pricing = {
    ...merged.Pricing,
    PriceId: managed.pricing.PriceId,
    IsAdvancedPricingModel: managed.pricing.IsAdvancedPricingModel,
  };

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
    `Merged: PriceId=${merged.Pricing.PriceId} (IsAdvancedPricingModel=${merged.Pricing.IsAdvancedPricingModel}), ` +
      `locales=[${Object.keys(managed.listings).join(', ')}]\n`,
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

if (import.meta.url === `file://${process.argv[1]}`) {
  main();
}
