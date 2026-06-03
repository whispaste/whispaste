/**
 * Tests for {@link fetchReleases} and {@link ReleaseFetcherError}.
 *
 * The public surface is `fetchReleases` (Promise-returning function) and
 * `ReleaseFetcherError` (error type with categorised `cause` field). All
 * tests stub `globalThis.fetch` via `vi.fn()` — never hit the network.
 */
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { fetchReleases, ReleaseFetcherError } from "../release-fetcher.ts";

type GitHubReleasePayload = {
  tag_name: string;
  name: string | null;
  published_at: string;
  body: string;
  html_url: string;
  prerelease: boolean;
  draft: boolean;
  assets?: { name: string; browser_download_url: string }[];
};

function makeRelease(overrides: Partial<GitHubReleasePayload> = {}): GitHubReleasePayload {
  return {
    tag_name: "v1.0.0",
    name: "Release 1.0.0",
    published_at: "2026-01-01T00:00:00Z",
    body: "Release notes",
    html_url: "https://github.com/owner/repo/releases/tag/v1.0.0",
    prerelease: false,
    draft: false,
    ...overrides,
  };
}

function jsonResponse(body: unknown, init: ResponseInit = {}): Response {
  return new Response(JSON.stringify(body), {
    status: 200,
    headers: { "Content-Type": "application/json" },
    ...init,
  });
}

function rawResponse(text: string, init: ResponseInit = {}): Response {
  return new Response(text, {
    status: 200,
    headers: { "Content-Type": "application/json" },
    ...init,
  });
}

let fetchMock: ReturnType<typeof vi.fn>;

beforeEach(() => {
  fetchMock = vi.fn();
  vi.stubGlobal("fetch", fetchMock);
});

afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

describe("fetchReleases", () => {
  it("returns up to 5 releases with all fields populated on the happy path", async () => {
    const payload = [
      makeRelease({
        tag_name: "v2.0.0",
        name: "Two",
        published_at: "2026-05-01T10:00:00Z",
        body: "Body two",
        html_url: "https://github.com/owner/repo/releases/tag/v2.0.0",
      }),
      makeRelease({
        tag_name: "v1.9.0",
        name: "One Nine",
        published_at: "2026-04-01T10:00:00Z",
        body: "Body 1.9",
        html_url: "https://github.com/owner/repo/releases/tag/v1.9.0",
      }),
    ];
    fetchMock.mockResolvedValue(jsonResponse(payload));

    const releases = await fetchReleases({ owner: "owner", repo: "repo" });

    expect(releases).toEqual([
      {
        tag: "v2.0.0",
        name: "Two",
        publishedAt: "2026-05-01T10:00:00Z",
        bodyMarkdown: "Body two",
        htmlUrl: "https://github.com/owner/repo/releases/tag/v2.0.0",
        isPrerelease: false,
        isDraft: false,
        deBodyMarkdown: null,
      },
      {
        tag: "v1.9.0",
        name: "One Nine",
        publishedAt: "2026-04-01T10:00:00Z",
        bodyMarkdown: "Body 1.9",
        htmlUrl: "https://github.com/owner/repo/releases/tag/v1.9.0",
        isPrerelease: false,
        isDraft: false,
        deBodyMarkdown: null,
      },
    ]);
  });

  it("sources deBodyMarkdown from the release-notes-de.md asset when present", async () => {
    const payload = [
      makeRelease({
        tag_name: "v1.2.33",
        assets: [
          {
            name: "release-notes-de.md",
            browser_download_url: "https://example.test/v1.2.33/release-notes-de.md",
          },
          {
            name: "WhisPaste-Setup.exe",
            browser_download_url: "https://example.test/v1.2.33/WhisPaste-Setup.exe",
          },
        ],
      }),
    ];
    fetchMock.mockImplementation(async (url: string) => {
      if (url.includes("release-notes-de.md")) {
        return rawResponse("### Neu in v1.2.33\n- etwas\n");
      }
      return jsonResponse(payload);
    });

    const releases = await fetchReleases({ owner: "o", repo: "r" });

    expect(releases).toHaveLength(1);
    expect(releases[0]?.deBodyMarkdown).toBe("### Neu in v1.2.33\n- etwas\n");
    // One call for the releases list + one for the German asset.
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it("leaves deBodyMarkdown null when the German asset fetch fails (no fallback)", async () => {
    const payload = [
      makeRelease({
        tag_name: "v1.2.33",
        assets: [
          {
            name: "release-notes-de.md",
            browser_download_url: "https://example.test/missing.md",
          },
        ],
      }),
    ];
    fetchMock.mockImplementation(async (url: string) => {
      if (url.includes("missing.md")) {
        return new Response("not found", { status: 404 });
      }
      return jsonResponse(payload);
    });

    const releases = await fetchReleases({ owner: "o", repo: "r" });

    expect(releases[0]?.deBodyMarkdown).toBeNull();
  });

  it("filters prerelease entries before applying the count cut", async () => {
    const payload = [
      makeRelease({ tag_name: "v3.0.0", prerelease: true }),
      makeRelease({ tag_name: "v2.0.0" }),
      makeRelease({ tag_name: "v1.0.0" }),
    ];
    fetchMock.mockResolvedValue(jsonResponse(payload));

    const releases = await fetchReleases({ owner: "o", repo: "r", count: 2 });

    expect(releases.map((r) => r.tag)).toEqual(["v2.0.0", "v1.0.0"]);
    expect(releases.every((r) => r.isPrerelease === false)).toBe(true);
  });

  it("filters draft entries before applying the count cut", async () => {
    const payload = [
      makeRelease({ tag_name: "v3.0.0", draft: true }),
      makeRelease({ tag_name: "v2.0.0" }),
      makeRelease({ tag_name: "v1.0.0" }),
    ];
    fetchMock.mockResolvedValue(jsonResponse(payload));

    const releases = await fetchReleases({ owner: "o", repo: "r", count: 2 });

    expect(releases.map((r) => r.tag)).toEqual(["v2.0.0", "v1.0.0"]);
    expect(releases.every((r) => r.isDraft === false)).toBe(true);
  });

  it("respects the count parameter when more releases are available", async () => {
    const payload = Array.from({ length: 10 }, (_, i) =>
      makeRelease({ tag_name: `v${10 - i}.0.0` }),
    );
    fetchMock.mockResolvedValue(jsonResponse(payload));

    const releases = await fetchReleases({ owner: "o", repo: "r", count: 3 });

    expect(releases).toHaveLength(3);
    expect(releases.map((r) => r.tag)).toEqual(["v10.0.0", "v9.0.0", "v8.0.0"]);
  });

  it("sets Authorization: Bearer <token> header when token is provided", async () => {
    fetchMock.mockResolvedValue(jsonResponse([]));

    await fetchReleases({ owner: "o", repo: "r", token: "secret-token" });

    expect(fetchMock).toHaveBeenCalledTimes(1);
    const [, init] = fetchMock.mock.calls[0] as [string, RequestInit];
    const headers = new Headers(init.headers);
    expect(headers.get("Authorization")).toBe("Bearer secret-token");
    expect(headers.get("Accept")).toBe("application/vnd.github+json");
  });

  it("does not set an Authorization header when no token is provided", async () => {
    fetchMock.mockResolvedValue(jsonResponse([]));

    await fetchReleases({ owner: "o", repo: "r" });

    const [, init] = fetchMock.mock.calls[0] as [string, RequestInit];
    const headers = new Headers(init.headers);
    expect(headers.has("Authorization")).toBe(false);
    expect(headers.get("Accept")).toBe("application/vnd.github+json");
  });

  it("throws ReleaseFetcherError with cause='network' when fetch rejects", async () => {
    fetchMock.mockRejectedValue(new Error("ECONNRESET"));

    await expect(fetchReleases({ owner: "o", repo: "r" })).rejects.toMatchObject({
      name: "ReleaseFetcherError",
      cause: "network",
    });
    await expect(fetchReleases({ owner: "o", repo: "r" })).rejects.toBeInstanceOf(
      ReleaseFetcherError,
    );
  });

  it("throws ReleaseFetcherError with cause='rate-limited' on HTTP 403 with rate-limit headers", async () => {
    fetchMock.mockResolvedValue(
      new Response("rate limit exceeded", {
        status: 403,
        headers: {
          "Content-Type": "application/json",
          "X-RateLimit-Remaining": "0",
          "X-RateLimit-Reset": "1700000000",
        },
      }),
    );

    await expect(fetchReleases({ owner: "o", repo: "r" })).rejects.toMatchObject({
      name: "ReleaseFetcherError",
      cause: "rate-limited",
    });
  });

  it("throws ReleaseFetcherError with cause='auth' on HTTP 401", async () => {
    fetchMock.mockResolvedValue(
      new Response("Bad credentials", {
        status: 401,
        headers: { "Content-Type": "application/json" },
      }),
    );

    await expect(
      fetchReleases({ owner: "o", repo: "r", token: "bad" }),
    ).rejects.toMatchObject({
      name: "ReleaseFetcherError",
      cause: "auth",
    });
  });

  it("throws ReleaseFetcherError with cause='parse' on malformed JSON body", async () => {
    fetchMock.mockResolvedValue(rawResponse("{not valid json"));

    await expect(fetchReleases({ owner: "o", repo: "r" })).rejects.toMatchObject({
      name: "ReleaseFetcherError",
      cause: "parse",
    });
  });

  it("throws ReleaseFetcherError with cause='parse' when payload shape is unexpected", async () => {
    fetchMock.mockResolvedValue(jsonResponse({ unexpected: "shape" }));

    await expect(fetchReleases({ owner: "o", repo: "r" })).rejects.toMatchObject({
      name: "ReleaseFetcherError",
      cause: "parse",
    });
  });

  it("defaults to count=5 and returns at most 5 releases", async () => {
    const payload = Array.from({ length: 8 }, (_, i) =>
      makeRelease({ tag_name: `v${8 - i}.0.0` }),
    );
    fetchMock.mockResolvedValue(jsonResponse(payload));

    const releases = await fetchReleases({ owner: "o", repo: "r" });

    expect(releases).toHaveLength(5);
  });

  it("performs no disk-IO and keeps no global state across calls (pure over inputs)", async () => {
    fetchMock
      .mockResolvedValueOnce(jsonResponse([makeRelease({ tag_name: "v1.0.0" })]))
      .mockResolvedValueOnce(jsonResponse([makeRelease({ tag_name: "v2.0.0" })]));

    const first = await fetchReleases({ owner: "a", repo: "b" });
    const second = await fetchReleases({ owner: "c", repo: "d" });

    expect(first[0].tag).toBe("v1.0.0");
    expect(second[0].tag).toBe("v2.0.0");
    // Each invocation issues its own request — no caching/global state.
    expect(fetchMock).toHaveBeenCalledTimes(2);
    const [url1] = fetchMock.mock.calls[0] as [string];
    const [url2] = fetchMock.mock.calls[1] as [string];
    expect(url1).toContain("/repos/a/b/releases");
    expect(url2).toContain("/repos/c/d/releases");
  });
});
