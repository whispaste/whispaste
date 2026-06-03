/**
 * Tests for {@link writeReleases} and {@link readReleases}.
 *
 * The atomic-write tests use a real `tmpdir` (`mkdtemp`) so that the actual
 * `writeFile → rename` interaction is exercised end-to-end against the real
 * filesystem — there is no value in mocking `fs` for behaviour that is itself
 * defined by `fs`. The "verify the temp file exists before the rename" check
 * is implemented by importing the module-under-test through a small wrapper
 * that re-exports `node:fs/promises.rename` so the test can intercept it via
 * Vitest's `vi.hoisted` factory — ESM module namespaces are read-only in
 * Node, so `vi.spyOn` against `node:fs/promises` does not work.
 *
 * Decision: real `tmpdir` everywhere. `memfs` would add a dependency without
 * exercising the rename semantics we actually care about.
 */
import { mkdtemp, readdir, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// Observer hook installed by the `vi.mock` below. Each test resets it in
// `beforeEach`. The mocked `rename` invokes this *before* delegating to the
// real `node:fs/promises.rename`, so tests can inspect the filesystem at the
// exact instant the rename is about to happen — that is the atomic-write
// load-bearing observation.
let renameObserver: ((from: string, to: string) => Promise<void> | void) | null = null;

vi.mock("node:fs/promises", async () => {
  const actual = await vi.importActual<typeof import("node:fs/promises")>(
    "node:fs/promises",
  );
  return {
    ...actual,
    rename: async (from: Parameters<typeof actual.rename>[0], to: Parameters<typeof actual.rename>[1]): Promise<void> => {
      if (renameObserver !== null) {
        await renameObserver(String(from), String(to));
      }
      return actual.rename(from, to);
    },
  };
});

import type { ReleaseBlocks } from "../markdown-to-blocks.ts";
import {
  CURRENT_SCHEMA_VERSION,
  readReleases,
  ReleaseStoreError,
  writeReleases,
  type ReleaseEntry,
  type ReleasesFile,
} from "../release-store.ts";

function makeBlocks(headline = "Highlights"): ReleaseBlocks {
  return { sections: [{ heading: headline, items: [{ body: "something" }] }] };
}

function makeEntry(overrides: Partial<ReleaseEntry> = {}): ReleaseEntry {
  return {
    tag: "v1.0.0",
    name: "Release 1.0.0",
    publishedAt: "2026-01-01T00:00:00Z",
    htmlUrl: "https://github.com/owner/repo/releases/tag/v1.0.0",
    en: { bodyMarkdown: "### Highlights\n- something\n", blocks: makeBlocks() },
    de: {
      bodyMarkdown: "### Highlights\n- etwas\n",
      blocks: makeBlocks(),
      translatedAt: "2026-01-01T00:01:00Z",
    },
    ...overrides,
  };
}

let tmpRoot: string;

beforeEach(async () => {
  tmpRoot = await mkdtemp(join(tmpdir(), "release-store-"));
  renameObserver = null;
});

afterEach(async () => {
  renameObserver = null;
  await rm(tmpRoot, { recursive: true, force: true });
  vi.restoreAllMocks();
});

describe("writeReleases — atomic write", () => {
  it("writes to <filePath>.tmp first, then renames to the final path (verified by mocking rename and inspecting the directory mid-call)", async () => {
    // Re-import the module-under-test in isolation so the hoisted mock above
    // applies. The `__mockState.observe` hook fires at the moment rename is
    // called — *after* writeFile resolved, *before* rename completes — so we
    // can assert both files' presence at that instant.
    const filePath = join(tmpRoot, "releases.json");
    const tempPath = `${filePath}.tmp`;

    const observed: {
      called: boolean;
      from: string;
      to: string;
      tmpExists: boolean;
      finalExists: boolean;
    } = { called: false, from: "", to: "", tmpExists: false, finalExists: false };

    renameObserver = async (from, to): Promise<void> => {
      observed.called = true;
      observed.from = from;
      observed.to = to;
      const entries = await readdir(tmpRoot);
      observed.tmpExists = entries.includes("releases.json.tmp");
      observed.finalExists = entries.includes("releases.json");
    };

    await writeReleases({
      filePath,
      releases: [makeEntry()],
      fetchedAt: "2026-05-14T12:00:00Z",
    });

    expect(observed.called).toBe(true);
    expect(observed.from).toBe(tempPath);
    expect(observed.to).toBe(filePath);
    expect(observed.tmpExists).toBe(true);
    expect(observed.finalExists).toBe(false);

    // After the rename, only the final file remains — no leftover `.tmp`.
    const after = await readdir(tmpRoot);
    expect(after).toEqual(["releases.json"]);
  });

  it("produces a JSON file whose top-level fields match the input", async () => {
    const filePath = join(tmpRoot, "releases.json");
    await writeReleases({
      filePath,
      releases: [makeEntry()],
      fetchedAt: "2026-05-14T12:00:00Z",
    });

    const raw = await readFile(filePath, "utf8");
    const parsed = JSON.parse(raw) as ReleasesFile;
    expect(parsed.schemaVersion).toBe(CURRENT_SCHEMA_VERSION);
    expect(parsed.fetchedAt).toBe("2026-05-14T12:00:00Z");
    expect(parsed.releases).toHaveLength(1);
    expect(parsed.releases[0]?.tag).toBe("v1.0.0");
  });

  it("defaults fetchedAt to 'now' when the caller omits it", async () => {
    const filePath = join(tmpRoot, "releases.json");
    const before = Date.now();
    await writeReleases({ filePath, releases: [] });
    const after = Date.now();

    const parsed = JSON.parse(await readFile(filePath, "utf8")) as ReleasesFile;
    const stamped = Date.parse(parsed.fetchedAt);
    expect(stamped).toBeGreaterThanOrEqual(before);
    expect(stamped).toBeLessThanOrEqual(after);
  });

  it("wraps low-level fs errors in a ReleaseStoreError with cause='io'", async () => {
    // Writing into a path whose parent directory does not exist must fail.
    const filePath = join(tmpRoot, "does", "not", "exist", "releases.json");
    await expect(
      writeReleases({ filePath, releases: [], fetchedAt: "2026-05-14T12:00:00Z" }),
    ).rejects.toMatchObject({
      name: "ReleaseStoreError",
      cause: "io",
    });
  });
});

describe("readReleases — happy path", () => {
  it("reads back a file written by writeReleases (all top-level fields)", async () => {
    const filePath = join(tmpRoot, "releases.json");
    const entry = makeEntry();
    await writeReleases({
      filePath,
      releases: [entry],
      fetchedAt: "2026-05-14T12:00:00Z",
    });

    const loaded = await readReleases(filePath);
    expect(loaded.schemaVersion).toBe(CURRENT_SCHEMA_VERSION);
    expect(loaded.fetchedAt).toBe("2026-05-14T12:00:00Z");
    expect(loaded.releases).toEqual([entry]);
  });

  it("is round-trip idempotent at schemaVersion=1 (write → read → write yields the same bytes)", async () => {
    const filePath = join(tmpRoot, "releases.json");
    const entries = [makeEntry(), makeEntry({ tag: "v1.1.0", name: "Release 1.1.0" })];

    await writeReleases({
      filePath,
      releases: entries,
      fetchedAt: "2026-05-14T12:00:00Z",
    });
    const firstBytes = await readFile(filePath, "utf8");

    const loaded = await readReleases(filePath);
    await writeReleases({
      filePath,
      releases: loaded.releases,
      schemaVersion: loaded.schemaVersion,
      fetchedAt: loaded.fetchedAt,
    });
    const secondBytes = await readFile(filePath, "utf8");

    expect(secondBytes).toBe(firstBytes);
  });
});

describe("readReleases — schema migration", () => {
  it("lifts a v0 fixture forward to the current schemaVersion (matches snapshot)", async () => {
    // Hand-rolled v0 fixture. The migration registry's v0→v1 step is a
    // structural no-op; the snapshot below pins the migrated output so any
    // future v1→v2 change has to update it deliberately.
    const v0: Record<string, unknown> = {
      schemaVersion: 0,
      fetchedAt: "2026-05-14T12:00:00Z",
      releases: [makeEntry()],
    };
    const filePath = join(tmpRoot, "releases.json");
    await writeFile(filePath, JSON.stringify(v0, null, 2), "utf8");

    const loaded = await readReleases(filePath);
    expect(loaded.schemaVersion).toBe(CURRENT_SCHEMA_VERSION);
    expect(loaded).toMatchSnapshot();
  });

  it("throws migration error when the file declares a schemaVersion higher than the module supports", async () => {
    const future: Record<string, unknown> = {
      schemaVersion: CURRENT_SCHEMA_VERSION + 5,
      fetchedAt: "2026-05-14T12:00:00Z",
      releases: [],
    };
    const filePath = join(tmpRoot, "releases.json");
    await writeFile(filePath, JSON.stringify(future), "utf8");

    await expect(readReleases(filePath)).rejects.toMatchObject({
      name: "ReleaseStoreError",
      cause: "schema",
    });
  });
});

describe("readReleases — error categorisation", () => {
  it("throws with cause='io' when the file does not exist", async () => {
    const filePath = join(tmpRoot, "does-not-exist.json");
    await expect(readReleases(filePath)).rejects.toMatchObject({
      name: "ReleaseStoreError",
      cause: "io",
    });
  });

  it("throws with cause='parse' on corrupt JSON (clear message, not a silent return)", async () => {
    const filePath = join(tmpRoot, "releases.json");
    await writeFile(filePath, "{this is not valid JSON", "utf8");

    let captured: unknown;
    try {
      await readReleases(filePath);
    } catch (err) {
      captured = err;
    }
    expect(captured).toBeInstanceOf(ReleaseStoreError);
    expect((captured as ReleaseStoreError).cause).toBe("parse");
    // Message must explicitly call out the file path so build logs are useful.
    expect((captured as Error).message).toContain(filePath);
    expect((captured as Error).message).toMatch(/invalid JSON/i);
  });

  it("throws with cause='schema' when the file is JSON but not the expected shape", async () => {
    const filePath = join(tmpRoot, "releases.json");
    await writeFile(filePath, JSON.stringify({ unexpected: true }), "utf8");

    await expect(readReleases(filePath)).rejects.toMatchObject({
      name: "ReleaseStoreError",
      cause: "schema",
    });
  });

  it("throws with cause='schema' when a release entry is missing required fields", async () => {
    const filePath = join(tmpRoot, "releases.json");
    const broken: ReleasesFile = {
      schemaVersion: CURRENT_SCHEMA_VERSION,
      fetchedAt: "2026-05-14T12:00:00Z",
      releases: [
        // Cast: deliberately malformed shape for the negative test.
        { tag: "v1.0.0" } as unknown as ReleaseEntry,
      ],
    };
    await writeFile(filePath, JSON.stringify(broken), "utf8");

    await expect(readReleases(filePath)).rejects.toMatchObject({
      name: "ReleaseStoreError",
      cause: "schema",
    });
  });

  it("accepts a release entry without a German body (de is optional, no-fallback pipeline)", async () => {
    const filePath = join(tmpRoot, "releases.json");
    const enOnly = makeEntry();
    delete (enOnly as { de?: unknown }).de;

    await writeReleases({
      filePath,
      releases: [enOnly],
      fetchedAt: "2026-05-14T12:00:00Z",
    });
    const loaded = await readReleases(filePath);

    expect(loaded.releases).toHaveLength(1);
    expect(loaded.releases[0]?.de).toBeUndefined();
    expect(loaded.releases[0]?.en.bodyMarkdown).toContain("Highlights");
  });
});
