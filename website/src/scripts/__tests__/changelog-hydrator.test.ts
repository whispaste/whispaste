// @vitest-environment jsdom
/**
 * Tests for {@link hydrate} — the browser-side changelog hydrator.
 *
 * One test per acceptance criterion in
 * `.scratch/dynamic-changelog/issues/06-changelog-hydrator.md`. Each test
 * documents the observable behaviour it locks in. `fetch` and `localStorage`
 * are mocked via `vi.fn()` and `vi.spyOn(...)` so we never hit the real
 * network and never persist test state across runs.
 */
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { hydrate, renderBlocksToHtml, type Release } from "../changelog-hydrator.ts";

type FetchMock = ReturnType<typeof vi.fn>;

const CACHE_KEY = "whispaste:changelog-cache";

/** Build a GitHub-API-shaped release payload. */
function ghRelease(overrides: Partial<{
  tag_name: string;
  name: string;
  published_at: string;
  body: string;
  html_url: string;
  draft: boolean;
  prerelease: boolean;
}> = {}): Record<string, unknown> {
  return {
    tag_name: "v1.2.14",
    name: "v1.2.14",
    published_at: "2026-05-14T10:00:00Z",
    body: "### Highlights\n- something new\n",
    html_url: "https://github.com/example/example/releases/tag/v1.2.14",
    draft: false,
    prerelease: false,
    ...overrides,
  };
}

function mockResponse(
  status: number,
  body: unknown,
  headers: Record<string, string> = {},
): Response {
  const hdrs = new Headers(headers);
  return {
    ok: status >= 200 && status < 300,
    status,
    headers: hdrs,
    json: async () => body,
  } as unknown as Response;
}

function setupMount(): HTMLOListElement {
  document.body.innerHTML = "";
  const list = document.createElement("ol");
  list.id = "changelog-list";
  // One pre-existing static card (tag v1.2.13) — must NEVER be removed.
  const existing = document.createElement("li");
  existing.dataset["staticTag"] = "v1.2.13";
  existing.textContent = "static-1.2.13";
  list.appendChild(existing);
  document.body.appendChild(list);
  return list;
}

/** Synchronously settle the hydrator's in-flight promise. */
async function flush(): Promise<void> {
  // Two macro-task ticks let `fetch().then(json).then(...)` resolve and let the
  // `.finally` clean up the in-flight lock.
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
}

let fetchMock: FetchMock;
let warnSpy: ReturnType<typeof vi.spyOn>;

beforeEach(() => {
  localStorage.clear();
  fetchMock = vi.fn();
  vi.stubGlobal("fetch", fetchMock);
  warnSpy = vi.spyOn(console, "warn").mockImplementation(() => undefined);
});

afterEach(() => {
  vi.unstubAllGlobals();
  warnSpy.mockRestore();
  document.body.innerHTML = "";
});

describe("AC1 — module exports `hydrate`", () => {
  it("exports a callable `hydrate` function returning a cleanup function", () => {
    expect(typeof hydrate).toBe("function");
    fetchMock.mockResolvedValue(mockResponse(200, []));
    setupMount();
    const cleanup = hydrate({
      mountSelector: "#changelog-list",
      owner: "o",
      repo: "r",
      cardRenderer: () => document.createElement("li"),
      currentTopVersion: "v1.2.13",
    });
    expect(typeof cleanup).toBe("function");
    cleanup();
  });
});

describe("AC3 — first page load (no cache): fetch, cache, prepend on newer", () => {
  it("performs a fetch, stores the cache, and prepends the new card", async () => {
    fetchMock.mockResolvedValue(
      mockResponse(200, [ghRelease({ tag_name: "v1.2.14" })], { etag: 'W/"abc"' }),
    );
    const list = setupMount();
    hydrate({
      mountSelector: "#changelog-list",
      owner: "silvio-lindstedt",
      repo: "whispaste",
      cardRenderer: (r) => {
        const li = document.createElement("li");
        li.textContent = r.tag;
        return li;
      },
      currentTopVersion: "v1.2.13",
    });
    await flush();
    expect(fetchMock).toHaveBeenCalledTimes(1);
    const cached = JSON.parse(localStorage.getItem(CACHE_KEY) ?? "{}") as {
      etag: string;
      releases: Release[];
    };
    expect(cached.etag).toBe('W/"abc"');
    expect(cached.releases).toHaveLength(1);
    expect(list.firstElementChild?.textContent).toBe("v1.2.14");
    // Static card is still present, untouched.
    expect(list.querySelector('[data-static-tag="v1.2.13"]')).not.toBeNull();
  });
});

describe("AC4 — cache hit within TTL: skip fetch", () => {
  it("does not call fetch when timestamp is fresher than ttlMs", async () => {
    localStorage.setItem(
      CACHE_KEY,
      JSON.stringify({
        etag: 'W/"old"',
        releases: [],
        timestamp: Date.now() - 1000,
      }),
    );
    setupMount();
    hydrate({
      mountSelector: "#changelog-list",
      owner: "o",
      repo: "r",
      cardRenderer: () => document.createElement("li"),
      currentTopVersion: "v1.2.13",
      ttlMs: 60_000,
    });
    await flush();
    expect(fetchMock).not.toHaveBeenCalled();
  });
});

describe("AC5 — cache miss + 304: only timestamp updates", () => {
  it("preserves releases/etag and updates timestamp only; no DOM change", async () => {
    const oldTs = Date.now() - 60 * 60 * 1000;
    localStorage.setItem(
      CACHE_KEY,
      JSON.stringify({
        etag: 'W/"old"',
        releases: [{ tag: "v1.2.13" }],
        timestamp: oldTs,
      }),
    );
    fetchMock.mockResolvedValue(mockResponse(304, null));
    const list = setupMount();
    const childCountBefore = list.childElementCount;
    hydrate({
      mountSelector: "#changelog-list",
      owner: "o",
      repo: "r",
      cardRenderer: () => {
        throw new Error("must not render on 304");
      },
      currentTopVersion: "v1.2.13",
      ttlMs: 1,
    });
    await flush();
    expect(fetchMock).toHaveBeenCalledTimes(1);
    const cached = JSON.parse(localStorage.getItem(CACHE_KEY) ?? "{}") as {
      etag: string;
      timestamp: number;
      releases: Array<{ tag: string }>;
    };
    expect(cached.etag).toBe('W/"old"');
    expect(cached.releases).toEqual([{ tag: "v1.2.13" }]);
    expect(cached.timestamp).toBeGreaterThan(oldTs);
    expect(list.childElementCount).toBe(childCountBefore);
  });

  it("passes the cached etag as `If-None-Match`", async () => {
    localStorage.setItem(
      CACHE_KEY,
      JSON.stringify({
        etag: 'W/"abc123"',
        releases: [],
        timestamp: Date.now() - 60 * 60 * 1000,
      }),
    );
    fetchMock.mockResolvedValue(mockResponse(304, null));
    setupMount();
    hydrate({
      mountSelector: "#changelog-list",
      owner: "o",
      repo: "r",
      cardRenderer: () => document.createElement("li"),
      currentTopVersion: "v1.2.13",
      ttlMs: 1,
    });
    await flush();
    expect(fetchMock).toHaveBeenCalledTimes(1);
    const args = fetchMock.mock.calls[0] as [string, { headers: Record<string, string> }];
    const init = args[1];
    const sent = init.headers;
    expect(sent["If-None-Match"]).toBe('W/"abc123"');
    expect(sent["Accept"]).toBe("application/vnd.github+json");
  });
});

describe("AC6 — 200 with newer top tag: prepends via cardRenderer", () => {
  it("only prepends releases newer than `currentTopVersion`", async () => {
    fetchMock.mockResolvedValue(
      mockResponse(200, [
        ghRelease({ tag_name: "v1.2.15", body: "### Highlights\n- newest\n" }),
        ghRelease({ tag_name: "v1.2.14", body: "### Highlights\n- middle\n" }),
        ghRelease({ tag_name: "v1.2.13", body: "### Highlights\n- existing\n" }),
      ]),
    );
    const list = setupMount();
    const seenTags: string[] = [];
    hydrate({
      mountSelector: "#changelog-list",
      owner: "o",
      repo: "r",
      cardRenderer: (r) => {
        seenTags.push(r.tag);
        const li = document.createElement("li");
        li.textContent = r.tag;
        return li;
      },
      currentTopVersion: "v1.2.13",
    });
    await flush();
    expect(seenTags.sort()).toEqual(["v1.2.14", "v1.2.15"]);
    // Newest must end up at the very top after sequential `prepend`.
    expect(list.firstElementChild?.textContent).toBe("v1.2.15");
    expect(list.children[1]?.textContent).toBe("v1.2.14");
    // Static card still in its original slot.
    expect(
      list.querySelector('[data-static-tag="v1.2.13"]')?.textContent,
    ).toBe("static-1.2.13");
  });
});

describe("AC7 — 200 with no new releases: no DOM change", () => {
  it("does not call cardRenderer when top tag equals currentTopVersion", async () => {
    fetchMock.mockResolvedValue(
      mockResponse(200, [ghRelease({ tag_name: "v1.2.13" })]),
    );
    const list = setupMount();
    const before = list.innerHTML;
    const renderer = vi.fn(() => document.createElement("li"));
    hydrate({
      mountSelector: "#changelog-list",
      owner: "o",
      repo: "r",
      cardRenderer: renderer,
      currentTopVersion: "v1.2.13",
    });
    await flush();
    expect(renderer).not.toHaveBeenCalled();
    expect(list.innerHTML).toBe(before);
  });
});

describe("AC8 — offline / network error: silent fail", () => {
  it("silently swallows fetch rejection; no DOM change; only console.warn", async () => {
    fetchMock.mockRejectedValue(new TypeError("Failed to fetch"));
    const list = setupMount();
    const before = list.innerHTML;
    hydrate({
      mountSelector: "#changelog-list",
      owner: "o",
      repo: "r",
      cardRenderer: () => document.createElement("li"),
      currentTopVersion: "v1.2.13",
    });
    await flush();
    expect(list.innerHTML).toBe(before);
    expect(warnSpy).toHaveBeenCalled();
  });
});

describe("AC9 — 403 rate-limited: silent fail, keeps cache", () => {
  it("preserves the existing cache on 403", async () => {
    const cachePayload = JSON.stringify({
      etag: 'W/"keepme"',
      releases: [{ tag: "v1.2.13" }],
      timestamp: Date.now() - 60 * 60 * 1000,
    });
    localStorage.setItem(CACHE_KEY, cachePayload);
    fetchMock.mockResolvedValue(
      mockResponse(403, { message: "API rate limit exceeded" }, {
        "X-RateLimit-Remaining": "0",
      }),
    );
    const list = setupMount();
    const before = list.innerHTML;
    hydrate({
      mountSelector: "#changelog-list",
      owner: "o",
      repo: "r",
      cardRenderer: () => document.createElement("li"),
      currentTopVersion: "v1.2.13",
      ttlMs: 1,
    });
    await flush();
    expect(list.innerHTML).toBe(before);
    expect(localStorage.getItem(CACHE_KEY)).toBe(cachePayload);
    expect(warnSpy).toHaveBeenCalled();
  });
});

describe("AC10 — 4xx / 5xx / parse error: silent fail", () => {
  it("silently fails on HTTP 500", async () => {
    fetchMock.mockResolvedValue(mockResponse(500, null));
    const list = setupMount();
    const before = list.innerHTML;
    hydrate({
      mountSelector: "#changelog-list",
      owner: "o",
      repo: "r",
      cardRenderer: () => document.createElement("li"),
      currentTopVersion: "v1.2.13",
    });
    await flush();
    expect(list.innerHTML).toBe(before);
    expect(warnSpy).toHaveBeenCalled();
  });

  it("silently fails when response JSON is unparseable", async () => {
    fetchMock.mockResolvedValue({
      ok: true,
      status: 200,
      headers: new Headers(),
      json: async () => {
        throw new SyntaxError("Unexpected end of JSON input");
      },
    } as unknown as Response);
    const list = setupMount();
    const before = list.innerHTML;
    hydrate({
      mountSelector: "#changelog-list",
      owner: "o",
      repo: "r",
      cardRenderer: () => document.createElement("li"),
      currentTopVersion: "v1.2.13",
    });
    await flush();
    expect(list.innerHTML).toBe(before);
    expect(warnSpy).toHaveBeenCalled();
  });

  it("silently fails when payload shape is not an array of releases", async () => {
    fetchMock.mockResolvedValue(mockResponse(200, { message: "nope" }));
    const list = setupMount();
    const before = list.innerHTML;
    hydrate({
      mountSelector: "#changelog-list",
      owner: "o",
      repo: "r",
      cardRenderer: () => document.createElement("li"),
      currentTopVersion: "v1.2.13",
    });
    await flush();
    expect(list.innerHTML).toBe(before);
    expect(warnSpy).toHaveBeenCalled();
  });
});

describe("AC11 — multiple hydrate calls: no double prepend", () => {
  it("a second hydrate call against the same mount does not duplicate cards", async () => {
    fetchMock.mockResolvedValue(
      mockResponse(200, [ghRelease({ tag_name: "v1.2.14" })]),
    );
    const list = setupMount();
    hydrate({
      mountSelector: "#changelog-list",
      owner: "o",
      repo: "r",
      cardRenderer: (r) => {
        const li = document.createElement("li");
        li.textContent = r.tag;
        return li;
      },
      currentTopVersion: "v1.2.13",
    });
    // Second call fires before the first one's fetch resolves.
    hydrate({
      mountSelector: "#changelog-list",
      owner: "o",
      repo: "r",
      cardRenderer: (r) => {
        const li = document.createElement("li");
        li.textContent = r.tag;
        return li;
      },
      currentTopVersion: "v1.2.13",
    });
    await flush();
    // Only one fetch issued (the second was locked out by the in-flight guard).
    expect(fetchMock).toHaveBeenCalledTimes(1);
    const cards = list.querySelectorAll('[data-hydrated-tag="v1.2.14"]');
    expect(cards.length).toBe(1);
  });

  it("re-hydrating after a fresh-cache hit does not re-prepend a tag already in the DOM", async () => {
    // First pass: 200 + prepend.
    fetchMock.mockResolvedValueOnce(
      mockResponse(200, [ghRelease({ tag_name: "v1.2.14" })]),
    );
    const list = setupMount();
    hydrate({
      mountSelector: "#changelog-list",
      owner: "o",
      repo: "r",
      cardRenderer: (r) => {
        const li = document.createElement("li");
        li.textContent = r.tag;
        return li;
      },
      currentTopVersion: "v1.2.13",
      ttlMs: 60_000,
    });
    await flush();
    expect(list.querySelectorAll('[data-hydrated-tag="v1.2.14"]').length).toBe(1);

    // Second pass: within TTL → no fetch, no duplicate.
    hydrate({
      mountSelector: "#changelog-list",
      owner: "o",
      repo: "r",
      cardRenderer: () => {
        throw new Error("must not render on cache hit");
      },
      currentTopVersion: "v1.2.13",
      ttlMs: 60_000,
    });
    await flush();
    expect(list.querySelectorAll('[data-hydrated-tag="v1.2.14"]').length).toBe(1);
  });
});

describe("AC12 — markdown rendering is XSS-safe", () => {
  it("does not produce executable <script> or inline-handler attributes", () => {
    const html = renderBlocksToHtml({
      sections: [
        {
          heading: "Highlights",
          items: [
            {
              body: "<script>window.PWNED = true;</script><img src=x onerror=alert(1)>",
            },
          ],
        },
      ],
    });
    // Mount the sanitised HTML and assert that no live `<script>` or DOM
    // element with an `onerror` attribute was created. The literal characters
    // may appear as escaped text content (`&lt;script&gt;`), which is safe.
    const host = document.createElement("div");
    host.innerHTML = html;
    expect(host.querySelector("script")).toBeNull();
    expect(host.querySelector("[onerror]")).toBeNull();
    expect(host.querySelector("img")).toBeNull();
    // Confirm the source was escaped (not executed) before sanitisation.
    expect(host.textContent).toContain("<script>");
  });

  it("uses DOMPurify to sanitise non-escaped HTML if it leaks in via headings", () => {
    const html = renderBlocksToHtml({
      sections: [
        {
          heading: "<img src=x onerror=alert(1)>",
          items: [],
        },
      ],
    });
    const host = document.createElement("div");
    host.innerHTML = html;
    expect(host.querySelector("[onerror]")).toBeNull();
  });
});

describe("AC13 — bundle-size budget (verified at build-time)", () => {
  it("hydrator source alone stays well under the 15 KB gzipped budget (sanity check)", async () => {
    // Sanity-check on the raw module size. Strict budget verification is done
    // post-build via `gzip -c < dist/_astro/<chunk>.js | wc -c` — see Evidence.
    const { readFile } = await import("node:fs/promises");
    const { gzipSync } = await import("node:zlib");
    // `process.cwd()` is `website/` when vitest runs from the package root.
    const source = await readFile(
      "src/scripts/changelog-hydrator.ts",
      "utf8",
    );
    const gzipped = gzipSync(source).length;
    // Source alone (pre-bundling, pre-dompurify) sits well under budget.
    expect(gzipped).toBeLessThan(15 * 1024);
  });
});

describe("AC14 — cleanup() releases the in-flight lock", () => {
  it("cleanup short-circuits a pending hydrate before it mutates DOM", async () => {
    const resolvers: Array<(value: Response) => void> = [];
    fetchMock.mockImplementation(
      () =>
        new Promise<Response>((resolve) => {
          resolvers.push(resolve);
        }),
    );
    const list = setupMount();
    const renderer = vi.fn(() => document.createElement("li"));
    const cleanup = hydrate({
      mountSelector: "#changelog-list",
      owner: "o",
      repo: "r",
      cardRenderer: renderer,
      currentTopVersion: "v1.2.13",
    });
    cleanup();
    // Now resolve the fetch — the hydrator must observe `cancelled` and skip
    // the cardRenderer call.
    resolvers[0]?.(mockResponse(200, [ghRelease({ tag_name: "v1.2.99" })]));
    await flush();
    expect(renderer).not.toHaveBeenCalled();
    expect(list.querySelector('[data-hydrated-tag="v1.2.99"]')).toBeNull();
  });
});

describe("AC15 — vitest suite runs green", () => {
  it("missing mount element causes a silent skip (no throw)", async () => {
    fetchMock.mockResolvedValue(mockResponse(200, []));
    document.body.innerHTML = "";
    expect(() => {
      hydrate({
        mountSelector: "#does-not-exist",
        owner: "o",
        repo: "r",
        cardRenderer: () => document.createElement("li"),
        currentTopVersion: "v1.2.13",
      });
    }).not.toThrow();
    await flush();
    // No fetch attempt either — we bail out cleanly.
    expect(fetchMock).not.toHaveBeenCalled();
  });
});
