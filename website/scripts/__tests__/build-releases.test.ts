/**
 * Tests for {@link buildReleases} — the build-time orchestrator that wires
 * fetcher → markdown-parser → translator → store into a single pipeline.
 *
 * Strategy: inject doubles via the `deps` seam so each underlying module's
 * behaviour is fully controllable. No network, no OpenAI, no filesystem.
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
  translateSpy: ReturnType<typeof vi.fn>;
  writeSpy: ReturnType<typeof vi.fn>;
  logger: LoggerSpy;
} {
  const fetchSpy = vi.fn(async () => [makeRelease()]);
  const parseSpy = vi.fn((md: string) => makeBlocks(md));
  const translateSpy = vi.fn(async ({ markdown }: { markdown: string }) =>
    `[de] ${markdown}`,
  );
  const writeSpy = vi.fn(async () => undefined);
  const logger = makeLogger();
  const deps: BuildReleasesDeps = {
    fetchReleases: fetchSpy as unknown as BuildReleasesDeps["fetchReleases"],
    parseReleaseBody: parseSpy as unknown as BuildReleasesDeps["parseReleaseBody"],
    translateBody: translateSpy as unknown as BuildReleasesDeps["translateBody"],
    writeReleases: writeSpy as unknown as BuildReleasesDeps["writeReleases"],
    logger: logger as unknown as BuildReleasesDeps["logger"],
    now: () => "2026-05-14T12:00:00.000Z",
    ...overrides,
  };
  return { deps, fetchSpy, parseSpy, translateSpy, writeSpy, logger };
}

describe("buildReleases — happy path", () => {
  it("calls fetcher → parser → translator → writer in order, composes a merged feed, and emits the three observability lines", async () => {
    const fetchSpy = vi.fn(async () => [
      makeRelease({ tag: "v1.0.0", bodyMarkdown: "### Highlights\n- a\n" }),
      makeRelease({ tag: "v1.1.0", bodyMarkdown: "### Highlights\n- b\n" }),
    ]);
    const { deps, parseSpy, translateSpy, writeSpy, logger } = makeDeps({
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

    // Each release: EN parse, DE translate, DE parse → 2 parses per release.
    expect(parseSpy).toHaveBeenCalledTimes(4);
    expect(translateSpy).toHaveBeenCalledTimes(2);
    expect(translateSpy.mock.calls[0]?.[0]).toMatchObject({
      markdown: "### Highlights\n- a\n",
      targetLang: "de",
    });

    // Writer called with the merged ReleaseEntry list.
    expect(writeSpy).toHaveBeenCalledTimes(1);
    const writeArg = writeSpy.mock.calls[0]?.[0] as {
      filePath: string;
      releases: Array<{ tag: string; en: { bodyMarkdown: string }; de: { bodyMarkdown: string; translatedAt: string } }>;
      schemaVersion: number;
    };
    expect(writeArg.filePath).toBe("/tmp/does-not-matter.json");
    expect(writeArg.schemaVersion).toBe(1);
    expect(writeArg.releases).toHaveLength(2);
    expect(writeArg.releases[0]?.tag).toBe("v1.0.0");
    expect(writeArg.releases[0]?.en.bodyMarkdown).toBe("### Highlights\n- a\n");
    expect(writeArg.releases[0]?.de.bodyMarkdown).toBe("[de] ### Highlights\n- a\n");
    expect(writeArg.releases[0]?.de.translatedAt).toBe("2026-05-14T12:00:00.000Z");

    // Observability lines
    const warned = logger.warn.mock.calls.map((c) => String(c[0]));
    expect(warned).toContain("[release-build] fetched 2 releases");
    expect(warned).toContain("[release-build] translated 2 bodies (0 cache-hits)");
    expect(warned).toContain("[release-build] fallback path used: no");

    // Returned counters
    expect(result).toEqual({
      fetchedCount: 2,
      translatedCount: 2,
      cacheHits: 0,
      fallbackUsed: false,
    });
  });

  it("counts cache hits via the injected TranslationCache", async () => {
    // First lookup hits, second misses — the orchestrator must surface 1 hit.
    let callCount = 0;
    const cache = {
      get: vi.fn(async () => {
        callCount++;
        return callCount === 1 ? "[de] cached body" : null;
      }),
      set: vi.fn(async () => undefined),
    };
    const { deps, logger } = makeDeps({
      fetchReleases: vi.fn(async () => [
        makeRelease({ tag: "v1.0.0", bodyMarkdown: "### Highlights\n- a\n" }),
        makeRelease({ tag: "v1.1.0", bodyMarkdown: "### Highlights\n- b\n" }),
      ]) as unknown as BuildReleasesDeps["fetchReleases"],
      cache,
      // translator must actually query the injected cache for the counter to
      // tick — simulate the real translator's "check cache, else translate".
      translateBody: vi.fn(async ({ markdown, cache: c }: { markdown: string; cache?: { get: (k: string) => Promise<string | null> } }) => {
        const hit = c ? await c.get("k") : null;
        return hit ?? `[de] ${markdown}`;
      }) as unknown as BuildReleasesDeps["translateBody"],
    });

    const result = await buildReleases({
      filePath: "/tmp/x.json",
      deps,
    });

    expect(result.cacheHits).toBe(1);
    const warned = logger.warn.mock.calls.map((c) => String(c[0]));
    expect(warned).toContain("[release-build] translated 2 bodies (1 cache-hits)");
  });
});

describe("buildReleases — fallback path", () => {
  it("falls back when fetchReleases throws: logs the marker, does not call writer, returns fallbackUsed=true", async () => {
    const fetchError = new ReleaseFetcherError("network", "boom");
    const fetchSpy = vi.fn(async () => {
      throw fetchError;
    });
    const writeSpy = vi.fn(async () => undefined);
    const translateSpy = vi.fn(async () => "x");
    const { deps, logger } = makeDeps({
      fetchReleases: fetchSpy as unknown as BuildReleasesDeps["fetchReleases"],
      writeReleases: writeSpy as unknown as BuildReleasesDeps["writeReleases"],
      translateBody: translateSpy as unknown as BuildReleasesDeps["translateBody"],
    });

    const result = await buildReleases({
      filePath: "/tmp/x.json",
      deps,
    });

    // Writer NOT called — the committed releases.json is left untouched.
    expect(writeSpy).not.toHaveBeenCalled();
    expect(translateSpy).not.toHaveBeenCalled();

    // Clearly-marked fallback warning, plus the three observability lines.
    const warned = logger.warn.mock.calls.map((c) => String(c[0]));
    expect(warned.some((line) => line.includes("[release-build] WARN: API unreachable, using committed releases.json"))).toBe(true);
    expect(warned).toContain("[release-build] fetched 0 releases");
    expect(warned).toContain("[release-build] translated 0 bodies (0 cache-hits)");
    expect(warned).toContain("[release-build] fallback path used: yes");

    expect(result).toEqual({
      fetchedCount: 0,
      translatedCount: 0,
      cacheHits: 0,
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
