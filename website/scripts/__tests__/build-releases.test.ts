/**
 * Tests for {@link buildReleases} — the build-time orchestrator that wires
 * fetcher → markdown-parser → store into a single pipeline.
 *
 * German bodies are sourced from each release's `release-notes-de.md` asset
 * (resolved by the fetcher into `Release.deBodyMarkdown`). There is no
 * translation step and no fallback — a release without the asset is persisted
 * English-only.
 *
 * Strategy: inject doubles via the `deps` seam so each underlying module's
 * behaviour is fully controllable. No network, no filesystem.
 */
import { describe, expect, it, vi } from "vitest";

import {
  buildReleases,
  type BuildReleasesDeps,
} from "../build-releases.ts";
import { ReleaseFetcherError, type Release } from "../release-fetcher.ts";
import type { ReleaseBlocks } from "../markdown-to-blocks.ts";

function makeRelease(overrides: Partial<Release> = {}): Release {
  return {
    tag: "v1.0.0",
    name: "Release 1.0.0",
    publishedAt: "2026-01-01T00:00:00Z",
    bodyMarkdown: "### Highlights\n- did a thing\n",
    htmlUrl: "https://github.com/whispaste/whispaste/releases/tag/v1.0.0",
    isPrerelease: false,
    isDraft: false,
    deBodyMarkdown: "### Höhepunkte\n- etwas getan\n",
    ...overrides,
  };
}

function makeBlocks(text: string): ReleaseBlocks {
  return { sections: [{ heading: "Highlights", items: [{ body: text }] }] };
}

type LoggerSpy = {
  warn: ReturnType<typeof vi.fn>;
  error: ReturnType<typeof vi.fn>;
};

function makeLogger(): LoggerSpy {
  return { warn: vi.fn(), error: vi.fn() };
}

/** Default deps where every module is a deterministic spy. */
function makeDeps(overrides: Partial<BuildReleasesDeps> = {}): {
  deps: BuildReleasesDeps;
  fetchSpy: ReturnType<typeof vi.fn>;
  parseSpy: ReturnType<typeof vi.fn>;
  writeSpy: ReturnType<typeof vi.fn>;
  logger: LoggerSpy;
} {
  const fetchSpy = vi.fn(async () => [makeRelease()]);
  const parseSpy = vi.fn((md: string) => makeBlocks(md));
  const writeSpy = vi.fn(async () => undefined);
  const logger = makeLogger();
  const deps: BuildReleasesDeps = {
    fetchReleases: fetchSpy as unknown as BuildReleasesDeps["fetchReleases"],
    parseReleaseBody: parseSpy as unknown as BuildReleasesDeps["parseReleaseBody"],
    writeReleases: writeSpy as unknown as BuildReleasesDeps["writeReleases"],
    logger: logger as unknown as BuildReleasesDeps["logger"],
    now: () => "2026-05-14T12:00:00.000Z",
    ...overrides,
  };
  return { deps, fetchSpy, parseSpy, writeSpy, logger };
}

describe("buildReleases — happy path", () => {
  it("calls fetcher → parser → writer in order, composes a bilingual feed from EN body + DE asset, and emits the three observability lines", async () => {
    const fetchSpy = vi.fn(async () => [
      makeRelease({
        tag: "v1.0.0",
        bodyMarkdown: "### Highlights\n- a\n",
        deBodyMarkdown: "### Höhepunkte\n- a-de\n",
      }),
      makeRelease({
        tag: "v1.1.0",
        bodyMarkdown: "### Highlights\n- b\n",
        deBodyMarkdown: "### Höhepunkte\n- b-de\n",
      }),
    ]);
    const { deps, parseSpy, writeSpy, logger } = makeDeps({
      fetchReleases: fetchSpy as unknown as BuildReleasesDeps["fetchReleases"],
    });

    const result = await buildReleases({
      filePath: "/tmp/does-not-matter.json",
      token: "ghs_test",
      deps,
    });

    // fetcher called with the project's owner/repo
    expect(fetchSpy).toHaveBeenCalledTimes(1);
    expect(fetchSpy).toHaveBeenCalledWith({
      owner: "whispaste",
      repo: "whispaste",
      count: 5,
      token: "ghs_test",
    });

    // Each release: EN parse + DE parse (asset present) → 2 parses per release.
    expect(parseSpy).toHaveBeenCalledTimes(4);

    // Writer called with the merged ReleaseEntry list.
    expect(writeSpy).toHaveBeenCalledTimes(1);
    const writeArg = writeSpy.mock.calls[0]?.[0] as {
      filePath: string;
      releases: Array<{
        tag: string;
        en: { bodyMarkdown: string };
        de?: { bodyMarkdown: string; translatedAt: string };
      }>;
      schemaVersion: number;
    };
    expect(writeArg.filePath).toBe("/tmp/does-not-matter.json");
    expect(writeArg.schemaVersion).toBe(1);
    expect(writeArg.releases).toHaveLength(2);
    expect(writeArg.releases[0]?.tag).toBe("v1.0.0");
    expect(writeArg.releases[0]?.en.bodyMarkdown).toBe("### Highlights\n- a\n");
    expect(writeArg.releases[0]?.de?.bodyMarkdown).toBe("### Höhepunkte\n- a-de\n");
    expect(writeArg.releases[0]?.de?.translatedAt).toBe("2026-05-14T12:00:00.000Z");

    // Observability lines
    const warned = logger.warn.mock.calls.map((c) => String(c[0]));
    expect(warned).toContain("[release-build] fetched 2 releases");
    expect(warned).toContain("[release-build] sourced 2 German bodies");
    expect(warned).toContain("[release-build] fallback path used: no");

    // Returned counters
    expect(result).toEqual({
      fetchedCount: 2,
      germanCount: 2,
      fallbackUsed: false,
    });
  });

  it("persists a release without a German asset as English-only (no fallback)", async () => {
    const fetchSpy = vi.fn(async () => [
      makeRelease({ tag: "v1.0.0", deBodyMarkdown: "### Höhepunkte\n- da\n" }),
      makeRelease({ tag: "v1.1.0", deBodyMarkdown: null }),
    ]);
    const { deps, parseSpy, writeSpy, logger } = makeDeps({
      fetchReleases: fetchSpy as unknown as BuildReleasesDeps["fetchReleases"],
    });

    const result = await buildReleases({ filePath: "/tmp/x.json", deps });

    // 2 EN parses + 1 DE parse (only the first release has a German body).
    expect(parseSpy).toHaveBeenCalledTimes(3);

    const writeArg = writeSpy.mock.calls[0]?.[0] as {
      releases: Array<{ tag: string; de?: unknown }>;
    };
    expect(writeArg.releases[0]?.de).toBeDefined();
    expect(writeArg.releases[1]?.de).toBeUndefined();

    expect(result).toEqual({
      fetchedCount: 2,
      germanCount: 1,
      fallbackUsed: false,
    });
    const warned = logger.warn.mock.calls.map((c) => String(c[0]));
    expect(warned).toContain("[release-build] sourced 1 German bodies");
  });
});

describe("buildReleases — fallback path", () => {
  it("falls back when fetchReleases throws: logs the marker, does not call writer, returns fallbackUsed=true", async () => {
    const fetchError = new ReleaseFetcherError("network", "boom");
    const fetchSpy = vi.fn(async () => {
      throw fetchError;
    });
    const writeSpy = vi.fn(async () => undefined);
    const { deps, logger } = makeDeps({
      fetchReleases: fetchSpy as unknown as BuildReleasesDeps["fetchReleases"],
      writeReleases: writeSpy as unknown as BuildReleasesDeps["writeReleases"],
    });

    const result = await buildReleases({
      filePath: "/tmp/x.json",
      deps,
    });

    // Writer NOT called — the committed releases.json is left untouched.
    expect(writeSpy).not.toHaveBeenCalled();

    // Clearly-marked fallback warning, plus the three observability lines.
    const warned = logger.warn.mock.calls.map((c) => String(c[0]));
    expect(warned.some((line) => line.includes("[release-build] WARN: API unreachable, using committed releases.json"))).toBe(true);
    expect(warned).toContain("[release-build] fetched 0 releases");
    expect(warned).toContain("[release-build] sourced 0 German bodies");
    expect(warned).toContain("[release-build] fallback path used: yes");

    expect(result).toEqual({
      fetchedCount: 0,
      germanCount: 0,
      fallbackUsed: true,
    });
  });

  it("falls back on a generic Error (non-ReleaseFetcherError) — the seam is throw-shape agnostic", async () => {
    const fetchSpy = vi.fn(async () => {
      throw new Error("DNS lookup failed");
    });
    const writeSpy = vi.fn(async () => undefined);
    const { deps, logger } = makeDeps({
      fetchReleases: fetchSpy as unknown as BuildReleasesDeps["fetchReleases"],
      writeReleases: writeSpy as unknown as BuildReleasesDeps["writeReleases"],
    });

    const result = await buildReleases({ filePath: "/tmp/x.json", deps });

    expect(result.fallbackUsed).toBe(true);
    expect(writeSpy).not.toHaveBeenCalled();
    const warned = logger.warn.mock.calls.map((c) => String(c[0]));
    expect(warned.some((line) => line.includes("DNS lookup failed"))).toBe(true);
  });
});
