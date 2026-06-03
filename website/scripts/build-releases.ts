/**
 * Build-time orchestrator that materialises `website/src/data/releases.json`
 * from the GitHub Releases API on every Astro deploy.
 *
 * Pipeline:
 *   1. `fetchReleases` — pulls the N most recent published releases from
 *      `whispaste/whispaste` via the GitHub REST API, each carrying the EN
 *      body plus the optional German body from its `release-notes-de.md` asset.
 *   2. `parseReleaseBody(en)` — turns each release body into structured EN blocks.
 *   3. `parseReleaseBody(de)` — when a German asset body is present, turns it
 *      into DE blocks. There is no translation step and no fallback: a release
 *      without the asset is persisted English-only.
 *   4. `writeReleases` — atomically writes the merged feed to `releases.json`.
 *
 * Build-time fallback: when {@link fetchReleases} throws (network outage,
 * auth failure, GitHub down), the orchestrator falls back to the previously
 * committed `releases.json`, logs a clearly-marked warning, and exits 0. The
 * Astro build therefore remains green even if GitHub is unreachable.
 *
 * Three observability lines are emitted on every run:
 *   - `[release-build] fetched N releases`
 *   - `[release-build] sourced K German bodies`
 *   - `[release-build] fallback path used: yes|no`
 *
 * Run with:
 *   cd website && node --experimental-strip-types --no-warnings \
 *     scripts/build-releases.ts
 *
 * Decision: implemented as `.ts` (not `.mjs`) so it shares the same typed
 * surface as the modules it orchestrates. Node 22+ executes `.ts` files
 * directly via `--experimental-strip-types` — no `tsx` dependency required.
 */
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { fetchReleases, type Release } from "./release-fetcher.ts";
import { parseReleaseBody } from "./markdown-to-blocks.ts";
import {
  writeReleases,
  type ReleaseEntry,
} from "./release-store.ts";

/** GitHub owner/repo for this project. */
const OWNER = "whispaste";
const REPO = "whispaste";

/** Number of releases to include in `releases.json`. */
const RELEASE_COUNT = 5;

/**
 * Build-time dependency seam — the orchestrator pulls each underlying module
 * through this object so tests can substitute deterministic doubles without
 * touching the network, OpenAI, or disk.
 */
export type BuildReleasesDeps = {
  fetchReleases: typeof fetchReleases;
  parseReleaseBody: typeof parseReleaseBody;
  writeReleases: typeof writeReleases;
  /** Logger seam (defaults to `console`). */
  logger?: {
    warn(...args: unknown[]): void;
    error(...args: unknown[]): void;
  };
  /** ISO timestamp for the German `translatedAt` field. Defaults to `new Date().toISOString()`. */
  now?: () => string;
};

export type BuildReleasesOptions = {
  /** Absolute path to write `releases.json` to. */
  filePath: string;
  /** GitHub token (optional — anonymous calls work but are rate-limited). */
  token?: string;
  /** Override dependencies (tests only — production wiring omits this). */
  deps?: Partial<BuildReleasesDeps>;
};

export type BuildReleasesResult = {
  fetchedCount: number;
  /** How many of the fetched releases carried a German asset body. */
  germanCount: number;
  fallbackUsed: boolean;
};

/**
 * Run the build-time release pipeline.
 *
 * Returns the observability counters so callers (and tests) can inspect what
 * happened. Never throws on `fetchReleases` failure — that path is the
 * fallback that keeps the deploy green.
 */
export async function buildReleases(
  options: BuildReleasesOptions,
): Promise<BuildReleasesResult> {
  const deps: BuildReleasesDeps = {
    fetchReleases: options.deps?.fetchReleases ?? fetchReleases,
    parseReleaseBody: options.deps?.parseReleaseBody ?? parseReleaseBody,
    writeReleases: options.deps?.writeReleases ?? writeReleases,
    logger: options.deps?.logger ?? console,
    now: options.deps?.now ?? ((): string => new Date().toISOString()),
  };
  const logger = deps.logger ?? console;

  // ─── 1. Fetch releases (fallback on any failure) ─────────────────────────
  let releases: Release[];
  try {
    releases = await deps.fetchReleases({
      owner: OWNER,
      repo: REPO,
      count: RELEASE_COUNT,
      token: options.token,
    });
  } catch (err) {
    // The committed `releases.json` is the fallback corpus — leaving the file
    // untouched preserves the previous deploy's content. Build stays green.
    logger.warn(
      `[release-build] WARN: API unreachable, using committed releases.json (${(err as Error).message})`,
    );
    logger.warn("[release-build] fetched 0 releases");
    logger.warn("[release-build] sourced 0 German bodies");
    logger.warn("[release-build] fallback path used: yes");
    return {
      fetchedCount: 0,
      germanCount: 0,
      fallbackUsed: true,
    };
  }
  logger.warn(`[release-build] fetched ${String(releases.length)} releases`);

  // ─── 2/3. Parse EN, and DE when the release carries a German asset ────────
  // No translation, no cache: German comes solely from each release's
  // `release-notes-de.md` asset (resolved by the fetcher). A release without
  // that asset is persisted English-only — there is no fallback.
  const translatedAt = deps.now ? deps.now() : new Date().toISOString();
  const entries: ReleaseEntry[] = [];
  let germanCount = 0;
  for (const release of releases) {
    const enBody = release.bodyMarkdown;
    const enBlocks = deps.parseReleaseBody(enBody);

    const entry: ReleaseEntry = {
      tag: release.tag,
      name: release.name,
      publishedAt: release.publishedAt,
      htmlUrl: release.htmlUrl,
      en: { bodyMarkdown: enBody, blocks: enBlocks },
    };

    const deBody = release.deBodyMarkdown;
    if (deBody !== null && deBody.length > 0) {
      entry.de = {
        bodyMarkdown: deBody,
        blocks: deps.parseReleaseBody(deBody),
        translatedAt,
      };
      germanCount++;
    }

    entries.push(entry);
  }
  logger.warn(`[release-build] sourced ${String(germanCount)} German bodies`);

  // ─── 4. Write the merged file ────────────────────────────────────────────
  await deps.writeReleases({
    filePath: options.filePath,
    releases: entries,
    schemaVersion: 1,
  });
  logger.warn("[release-build] fallback path used: no");

  return {
    fetchedCount: releases.length,
    germanCount,
    fallbackUsed: false,
  };
}

/**
 * CLI entry point — only executed when this file is run directly (not when
 * imported by tests). Resolves the output path relative to this file's
 * location so it works regardless of the CWD the workflow uses.
 */
async function main(): Promise<void> {
  const here = dirname(fileURLToPath(import.meta.url));
  const outPath = resolve(here, "..", "src", "data", "releases.json");
  const token = process.env["GITHUB_TOKEN"];

  await buildReleases({ filePath: outPath, token });
}

// Run main() only when invoked as a script (Node sets import.meta.url to the
// resolved file URL; argv[1] is the entrypoint). The check keeps the module
// safely importable from tests.
const invokedDirectly =
  typeof process !== "undefined" &&
  process.argv[1] !== undefined &&
  fileURLToPath(import.meta.url) === resolve(process.argv[1]);

if (invokedDirectly) {
  await main();
}
