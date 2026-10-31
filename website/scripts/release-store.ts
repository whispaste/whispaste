/**
 * Build-time module that materialises the merged release feed (EN + DE plus
 * structured {@link ReleaseBlocks}) to disk as `releases.json` and reads it
 * back. The on-disk file is the single source of truth that Astro consumes at
 * build-time — see issue 07 for the wiring.
 *
 * Persistence guarantees:
 *   - Writes are **atomic**: the payload is first written to `<filePath>.tmp`
 *     and then renamed onto `filePath`. A crash mid-write leaves either the
 *     previous content or no file at all — never a half-written one.
 *   - The file carries an explicit `schemaVersion` so that future shape
 *     changes can be migrated forward without losing data. {@link readReleases}
 *     applies migrations transparently before returning.
 *   - Corrupt JSON or missing required fields throw a {@link ReleaseStoreError}
 *     with a categorised `cause`. Callers must decide whether to fall back to
 *     a stale copy or fail the build.
 *
 * This module composes the outputs of:
 *   - {@link ./release-fetcher.ts}     — raw {@link Release} list (EN body +
 *     optional German body from the `release-notes-de.md` asset),
 *   - {@link ./markdown-to-blocks.ts}  — {@link ReleaseBlocks} per body.
 *
 * The actual orchestration that produces a {@link ReleaseEntry} list lives in
 * the deploy workflow (issue 07); this module only owns the persistent layer.
 *
 * @example
 *   await writeReleases({
 *     filePath: "src/data/releases.json",
 *     releases,
 *     schemaVersion: CURRENT_SCHEMA_VERSION,
 *   });
 *   const { fetchedAt, releases: loaded } = await readReleases(
 *     "src/data/releases.json",
 *   );
 */
import { readFile, rename, writeFile } from "node:fs/promises";

import type { ReleaseBlocks } from "./markdown-to-blocks.ts";

/**
 * The schema version this module writes. Bumping this number requires adding
 * a corresponding migration entry in {@link MIGRATIONS} so older on-disk files
 * can be lifted forward by {@link readReleases}.
 */
export const CURRENT_SCHEMA_VERSION = 1;

/** Per-language payload for a single release. */
export type ReleaseLocale = {
  /** The original (or translated) body markdown for this language. */
  bodyMarkdown: string;
  /** Structured representation of the body — produced by `parseReleaseBody`. */
  blocks: ReleaseBlocks;
};

/** A single merged release entry persisted in `releases.json`. */
export type ReleaseEntry = {
  tag: string;
  name: string;
  publishedAt: string;
  htmlUrl: string;
  /** English (source) payload — pulled directly from the GitHub release body. */
  en: ReleaseLocale;
  /**
   * German payload — sourced from the release's `release-notes-de.md` asset.
   * Optional: releases published before the bilingual-asset pipeline (or any
   * release whose German asset is missing) simply carry no `de` block. There
   * is deliberately no translation fallback — `de` is present iff the asset
   * was. `translatedAt` records when the German body was materialised.
   */
  de?: ReleaseLocale & { translatedAt: string };
};

/** Top-level file shape that {@link readReleases} returns and {@link writeReleases} writes. */
export type ReleasesFile = {
  schemaVersion: number;
  /** ISO timestamp recording when the underlying GitHub data was fetched. */
  fetchedAt: string;
  releases: ReleaseEntry[];
};

/** Categorised failure modes for {@link ReleaseStoreError}. */
export type ReleaseStoreCause =
  | "io"
  | "parse"
  | "schema"
  | "migration";

/**
 * Error thrown by {@link readReleases} (and surfaced by {@link writeReleases})
 * with a categorised `cause` so callers can branch on recoverable conditions.
 */
export class ReleaseStoreError extends Error {
  public readonly cause: ReleaseStoreCause;

  constructor(
    cause: ReleaseStoreCause,
    message: string,
    options?: { cause?: unknown },
  ) {
    super(message);
    this.name = "ReleaseStoreError";
    this.cause = cause;
    if (options?.cause !== undefined) {
      Object.defineProperty(this, "originalCause", {
        value: options.cause,
        enumerable: false,
      });
    }
  }
}

export type WriteReleasesOptions = {
  /** Absolute or repo-relative path the final `releases.json` is written to. */
  filePath: string;
  releases: ReleaseEntry[];
  /**
   * Schema version to stamp on the file. Defaults to {@link CURRENT_SCHEMA_VERSION}.
   * Tests may pass an older number to construct fixtures, but production
   * callers should omit this and use the default.
   */
  schemaVersion?: number;
  /**
   * ISO timestamp to record on the file. Defaults to `new Date().toISOString()`
   * so build pipelines get a fresh marker without having to thread a clock
   * through. Tests pass a fixed string for determinism.
   *
   * Decision: caller-overridable but defaults to "now" — keeps the common
   * build-time call site terse (`writeReleases({ filePath, releases })`).
   */
  fetchedAt?: string;
};

/**
 * Atomically write the merged release feed to `filePath`.
 *
 * The payload is JSON-serialised, written to `<filePath>.tmp`, and then
 * renamed onto `filePath`. `fs.rename` is atomic within a single filesystem
 * on POSIX and on NTFS — readers therefore either see the previous file or
 * the new one, never a partial write.
 */
export async function writeReleases(
  options: WriteReleasesOptions,
): Promise<void> {
  const {
    filePath,
    releases,
    schemaVersion = CURRENT_SCHEMA_VERSION,
    fetchedAt = new Date().toISOString(),
  } = options;

  const payload: ReleasesFile = {
    schemaVersion,
    fetchedAt,
    releases,
  };
  const serialised = `${JSON.stringify(payload, null, 2)}\n`;

  const tempPath = `${filePath}.tmp`;
  try {
    await writeFile(tempPath, serialised, "utf8");
    await rename(tempPath, filePath);
  } catch (err) {
    throw new ReleaseStoreError(
      "io",
      `Failed to atomically write releases to ${filePath}: ${(err as Error).message}`,
      { cause: err },
    );
  }
}

/**
 * Read and validate the releases file at `filePath`.
 *
 * Behaviour:
 *   - Reads UTF-8 JSON, throws {@link ReleaseStoreError} with cause `"io"` if
 *     the file does not exist or cannot be read.
 *   - Throws cause `"parse"` if the file is not valid JSON.
 *   - Throws cause `"schema"` if the top-level shape is wrong (missing
 *     `schemaVersion` / `releases`, wrong types, …).
 *   - If `schemaVersion < CURRENT_SCHEMA_VERSION`, walks the {@link MIGRATIONS}
 *     chain forward. Each step that fails throws cause `"migration"`.
 *   - Returns the migrated file with `schemaVersion === CURRENT_SCHEMA_VERSION`.
 */
export async function readReleases(filePath: string): Promise<ReleasesFile> {
  let raw: string;
  try {
    raw = await readFile(filePath, "utf8");
  } catch (err) {
    throw new ReleaseStoreError(
      "io",
      `Failed to read releases file ${filePath}: ${(err as Error).message}`,
      { cause: err },
    );
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch (err) {
    throw new ReleaseStoreError(
      "parse",
      `Releases file ${filePath} contains invalid JSON: ${(err as Error).message}`,
      { cause: err },
    );
  }

  if (!isObject(parsed)) {
    throw new ReleaseStoreError(
      "schema",
      `Releases file ${filePath} is not a JSON object.`,
    );
  }

  const schemaVersion = (parsed as { schemaVersion?: unknown }).schemaVersion;
  if (typeof schemaVersion !== "number" || !Number.isInteger(schemaVersion)) {
    throw new ReleaseStoreError(
      "schema",
      `Releases file ${filePath} is missing an integer "schemaVersion".`,
    );
  }
  if (schemaVersion > CURRENT_SCHEMA_VERSION) {
    throw new ReleaseStoreError(
      "schema",
      `Releases file ${filePath} declares schemaVersion=${schemaVersion} but the highest supported version is ${CURRENT_SCHEMA_VERSION}. Refusing to downgrade.`,
    );
  }

  // Migration chain: each entry lifts the file from version `n` to `n + 1`.
  let current: Record<string, unknown> = parsed as Record<string, unknown>;
  for (let v = schemaVersion; v < CURRENT_SCHEMA_VERSION; v++) {
    const migrate = MIGRATIONS[v];
    if (migrate === undefined) {
      throw new ReleaseStoreError(
        "migration",
        `Releases file ${filePath} is at schemaVersion=${v} but no migration to ${v + 1} is registered.`,
      );
    }
    try {
      current = migrate(current);
    } catch (err) {
      throw new ReleaseStoreError(
        "migration",
        `Migration from schemaVersion=${v} to ${v + 1} failed for ${filePath}: ${(err as Error).message}`,
        { cause: err },
      );
    }
    current = { ...current, schemaVersion: v + 1 };
  }

  return assertReleasesFile(current, filePath);
}

/**
 * Migration registry. The key `n` holds the function that lifts a file from
 * schemaVersion `n` to `n + 1`. For the initial v1 schema this map is empty
 * — but the wiring is in place so future schema bumps only have to add one
 * entry without touching {@link readReleases}.
 *
 * Migration functions receive and return a plain `Record<string, unknown>`
 * (the migrating-payload shape is intentionally untyped: each migration knows
 * its own old shape and produces the next one). {@link readReleases} validates
 * the final result against {@link ReleasesFile} after the last step.
 */
const MIGRATIONS: Readonly<
  Record<number, (input: Record<string, unknown>) => Record<string, unknown>>
> = Object.freeze({
  // Example: lifting a hypothetical v0 file to v1. v0 is treated as identical
  // to v1 except that `schemaVersion` is absent or wrong — the
  // migration-infrastructure smoke test (see release-store.test.ts) exercises
  // this path by constructing a v0 fixture and asserting it becomes v1.
  0: (input: Record<string, unknown>): Record<string, unknown> => {
    // v0 → v1 is a structural no-op: only the version stamp changes. We still
    // return a fresh object so the caller can safely overlay `schemaVersion`.
    return { ...input };
  },
});

/** Validate that `value` matches {@link ReleasesFile}; throw if it doesn't. */
function assertReleasesFile(
  value: Record<string, unknown>,
  filePath: string,
): ReleasesFile {
  const fetchedAt = value.fetchedAt;
  if (typeof fetchedAt !== "string" || fetchedAt.length === 0) {
    throw new ReleaseStoreError(
      "schema",
      `Releases file ${filePath} is missing a non-empty "fetchedAt" string.`,
    );
  }
  const releases = value.releases;
  if (!Array.isArray(releases)) {
    throw new ReleaseStoreError(
      "schema",
      `Releases file ${filePath} is missing a "releases" array.`,
    );
  }
  for (const [i, entry] of releases.entries()) {
    if (!isReleaseEntry(entry)) {
      throw new ReleaseStoreError(
        "schema",
        `Releases file ${filePath} contains an invalid release entry at index ${i}.`,
      );
    }
  }
  const schemaVersion = value.schemaVersion;
  if (typeof schemaVersion !== "number") {
    // Should be unreachable because readReleases validates this before
    // migrating, but defensive shape-check keeps the cast below honest.
    throw new ReleaseStoreError(
      "schema",
      `Releases file ${filePath} lost its schemaVersion during migration.`,
    );
  }
  return {
    schemaVersion,
    fetchedAt,
    releases: releases as ReleaseEntry[],
  };
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isReleaseBlocks(value: unknown): value is ReleaseBlocks {
  if (!isObject(value)) return false;
  const sections = (value as { sections?: unknown }).sections;
  return Array.isArray(sections);
}

function isReleaseLocale(value: unknown): value is ReleaseLocale {
  if (!isObject(value)) return false;
  return (
    typeof (value as { bodyMarkdown?: unknown }).bodyMarkdown === "string" &&
    isReleaseBlocks((value as { blocks?: unknown }).blocks)
  );
}

function isReleaseEntry(value: unknown): value is ReleaseEntry {
  if (!isObject(value)) return false;
  const v = value as Record<string, unknown>;
  if (
    typeof v.tag !== "string" ||
    typeof v.name !== "string" ||
    typeof v.publishedAt !== "string" ||
    typeof v.htmlUrl !== "string"
  ) {
    return false;
  }
  if (!isReleaseLocale(v.en)) return false;
  // `de` is optional (no-fallback bilingual pipeline). When present it must be
  // a valid locale carrying a `translatedAt` string; when absent the entry is
  // still valid and renders English-only.
  const de = v.de;
  if (de !== undefined) {
    if (!isReleaseLocale(de)) return false;
    if (typeof (de as { translatedAt?: unknown }).translatedAt !== "string") {
      return false;
    }
  }
  return true;
}
