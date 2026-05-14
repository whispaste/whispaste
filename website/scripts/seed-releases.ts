/**
 * One-shot build-time helper that materialises a seed `releases.json` from
 * the legacy `website/src/data/changelog.json` source-of-truth, so that the
 * Astro page can switch to the new schema without waiting for the full
 * deploy-pipeline rebuild (issue 07).
 *
 * The script reads the legacy bilingual entries (highlights + improvements
 * arrays), folds each language into a single markdown body of the form
 *   ### Highlights
 *   - …
 *
 *   ### Improvements
 *   - …
 * runs it through {@link parseReleaseBody} so the resulting {@link ReleaseEntry}
 * carries the same structured `blocks` shape that the GitHub-driven flow will
 * produce, and writes the final {@link ReleasesFile} via {@link writeReleases}.
 *
 * It is intentionally a single-purpose script — it has no flags, no CLI, and
 * does not try to be incremental. Re-running it always rebuilds the seed file
 * from scratch.
 *
 * Run with:
 *   cd website && npx tsx scripts/seed-releases.ts
 *
 * Decision: kept as a checked-in TypeScript file (rather than hand-writing
 * `releases.json`) so the EN/DE bodies and `blocks` stay in sync mechanically
 * if the legacy file is ever edited before issue 07 retires it.
 */
import { readFile } from "node:fs/promises";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

import { parseReleaseBody } from "./markdown-to-blocks.ts";
import {
  writeReleases,
  type ReleaseEntry,
} from "./release-store.ts";

type LegacyLocale = {
  highlights: string[];
  improvements: string[];
};

type LegacyEntry = {
  version: string;
  date: string;
  en: LegacyLocale;
  de: LegacyLocale;
};

/** GitHub owner/repo used to build `htmlUrl` for each release. */
const OWNER = "whispaste";
const REPO = "whispaste";

/**
 * Render a bilingual legacy locale block as the body markdown shape the new
 * schema expects. Empty bullet arrays are emitted as a heading with no items
 * (which {@link parseReleaseBody} preserves as `items: []`) rather than being
 * dropped — keeps EN/DE structurally symmetric.
 */
function localeToMarkdown(locale: LegacyLocale): string {
  const parts: string[] = [];
  parts.push("### Highlights");
  for (const item of locale.highlights) {
    parts.push(`- ${item}`);
  }
  if (locale.improvements.length > 0) {
    parts.push("");
    parts.push("### Improvements");
    for (const item of locale.improvements) {
      parts.push(`- ${item}`);
    }
  }
  return parts.join("\n");
}

/**
 * Convert a `YYYY-MM-DD` date string into a normalised ISO timestamp at noon
 * UTC. Noon (rather than midnight) avoids accidental date drift across
 * timezone-rendering consumers that strip the time component.
 */
function dateToIso(date: string): string {
  return `${date}T12:00:00.000Z`;
}

function toReleaseEntry(entry: LegacyEntry, translatedAt: string): ReleaseEntry {
  const tag = `v${entry.version}`;
  const enBody = localeToMarkdown(entry.en);
  const deBody = localeToMarkdown(entry.de);
  return {
    tag,
    name: tag,
    publishedAt: dateToIso(entry.date),
    htmlUrl: `https://github.com/${OWNER}/${REPO}/releases/tag/${tag}`,
    en: {
      bodyMarkdown: enBody,
      blocks: parseReleaseBody(enBody),
    },
    de: {
      bodyMarkdown: deBody,
      blocks: parseReleaseBody(deBody),
      translatedAt,
    },
  };
}

async function main(): Promise<void> {
  const here = dirname(fileURLToPath(import.meta.url));
  const legacyPath = resolve(here, "..", "src", "data", "changelog.json");
  const outPath = resolve(here, "..", "src", "data", "releases.json");

  const raw = await readFile(legacyPath, "utf8");
  const legacy = JSON.parse(raw) as LegacyEntry[];

  // Deterministic timestamps so reruns produce identical JSON: anchor on the
  // legacy file's most-recent date rather than `Date.now()`.
  const newestDate = legacy
    .map((e) => e.date)
    .sort()
    .reverse()[0];
  const fetchedAt = dateToIso(newestDate ?? "2026-01-01");
  const translatedAt = fetchedAt;

  const releases = legacy.map((e) => toReleaseEntry(e, translatedAt));
  await writeReleases({
    filePath: outPath,
    releases,
    fetchedAt,
  });

  console.warn(`[seed-releases] wrote ${String(releases.length)} releases to ${outPath}`);
}

await main();
