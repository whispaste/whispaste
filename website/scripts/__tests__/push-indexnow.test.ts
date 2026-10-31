/**
 * Tests für den IndexNow-Submission-Post-Build-Hook (`push-indexnow.mjs`).
 *
 * Geprüfte Pure-Funktionen:
 *   - `extractUrlsFromSitemap(xml)` — parst `<loc>`-Einträge aus einer
 *     Astro-generierten Sitemap (`sitemap-0.xml`) und liefert die URL-Liste
 *     in Document-Reihenfolge.
 *   - `buildPayload({ host, key, keyLocation, urls })` — produziert das
 *     IndexNow-JSON-Body-Objekt nach Protokoll-Spec
 *     (https://www.indexnow.org/documentation).
 *   - `submitIndexNow(payload, { fetch, dryRun })` — POSTet das Payload mit
 *     korrekter URL + Headers, liefert die Response zurück; bei `dryRun: true`
 *     wird `fetch` NICHT aufgerufen.
 *   - `main({ fetch, env, readSitemap })` — Orchestrator. Ohne `INDEXNOW_KEY`
 *     loggt "skipped" und ruft `fetch` nicht auf.
 *
 * Tests vermeiden alle Netzwerk- und Filesystem-Zugriffe: `fetch` und
 * `readSitemap` werden als Mocks injiziert, der IndexNow-Endpoint wird NIE
 * real aufgerufen.
 */
import { describe, expect, it, vi } from "vitest";
import {
  INDEXNOW_ENDPOINT,
  buildPayload,
  extractUrlsFromSitemap,
  main,
  submitIndexNow,
} from "../push-indexnow.mjs";

const MOCK_SITEMAP_XML = `<?xml version="1.0" encoding="UTF-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml"><url><loc>https://whispaste.de/</loc><xhtml:link rel="alternate" hreflang="de" href="https://whispaste.de/"/><xhtml:link rel="alternate" hreflang="en" href="https://whispaste.de/en/"/></url><url><loc>https://whispaste.de/download/</loc></url><url><loc>https://whispaste.de/en/</loc></url><url><loc>https://whispaste.de/en/download/</loc></url></urlset>`;

describe("extractUrlsFromSitemap", () => {
  it("returns all <loc> entries in document order", () => {
    const urls = extractUrlsFromSitemap(MOCK_SITEMAP_XML);
    expect(urls).toEqual([
      "https://whispaste.de/",
      "https://whispaste.de/download/",
      "https://whispaste.de/en/",
      "https://whispaste.de/en/download/",
    ]);
  });

  it("ignores <xhtml:link href=...> attributes — only <loc> elements count", () => {
    // The mock sitemap contains `href="https://whispaste.de/en/"` inside
    // an `xhtml:link` element. That attribute must NOT show up as a
    // duplicate URL — only `<loc>` content is submitted.
    const urls = extractUrlsFromSitemap(MOCK_SITEMAP_XML);
    const counts = urls.reduce<Record<string, number>>((acc, u) => {
      acc[u] = (acc[u] ?? 0) + 1;
      return acc;
    }, {});
    for (const u of Object.values(counts)) {
      expect(u).toBe(1);
    }
  });

  it("returns an empty array for an empty urlset", () => {
    const xml = `<?xml version="1.0" encoding="UTF-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"></urlset>`;
    expect(extractUrlsFromSitemap(xml)).toEqual([]);
  });

  it("decodes XML entities in <loc> content", () => {
    const xml = `<?xml version="1.0"?><urlset><url><loc>https://whispaste.de/?a=1&amp;b=2</loc></url></urlset>`;
    expect(extractUrlsFromSitemap(xml)).toEqual([
      "https://whispaste.de/?a=1&b=2",
    ]);
  });
});

describe("buildPayload", () => {
  it("produces a JSON object with host, key, keyLocation, urlList per IndexNow spec", () => {
    const payload = buildPayload({
      host: "whispaste.de",
      key: "abc123",
      keyLocation: "https://whispaste.de/abc123.txt",
      urls: ["https://whispaste.de/", "https://whispaste.de/download/"],
    });
    expect(payload).toEqual({
      host: "whispaste.de",
      key: "abc123",
      keyLocation: "https://whispaste.de/abc123.txt",
      urlList: ["https://whispaste.de/", "https://whispaste.de/download/"],
    });
  });
});

describe("submitIndexNow", () => {
  it("POSTs to the IndexNow endpoint with application/json body", async () => {
    const fakeFetch = vi.fn().mockResolvedValue(
      new Response("", { status: 200, statusText: "OK" }),
    );
    const payload = buildPayload({
      host: "whispaste.de",
      key: "abc123",
      keyLocation: "https://whispaste.de/abc123.txt",
      urls: ["https://whispaste.de/"],
    });
    const res = await submitIndexNow(payload, { fetch: fakeFetch });
    expect(fakeFetch).toHaveBeenCalledTimes(1);
    const [url, init] = fakeFetch.mock.calls[0];
    expect(url).toBe(INDEXNOW_ENDPOINT);
    expect(init.method).toBe("POST");
    expect(init.headers).toMatchObject({
      "Content-Type": "application/json; charset=utf-8",
    });
    expect(JSON.parse(init.body)).toEqual(payload);
    expect(res.status).toBe(200);
  });

  it("does NOT call fetch when dryRun is true", async () => {
    const fakeFetch = vi.fn();
    const payload = buildPayload({
      host: "whispaste.de",
      key: "abc123",
      keyLocation: "https://whispaste.de/abc123.txt",
      urls: ["https://whispaste.de/"],
    });
    const res = await submitIndexNow(payload, {
      fetch: fakeFetch,
      dryRun: true,
    });
    expect(fakeFetch).not.toHaveBeenCalled();
    expect(res.status).toBe(0);
    expect(res.dryRun).toBe(true);
  });
});

describe("main", () => {
  it("skips submission and returns exit 0 when INDEXNOW_KEY is absent", async () => {
    const fakeFetch = vi.fn();
    const result = await main({
      fetch: fakeFetch,
      env: {},
      readSitemap: async () => MOCK_SITEMAP_XML,
    });
    expect(fakeFetch).not.toHaveBeenCalled();
    expect(result.skipped).toBe(true);
    expect(result.exitCode).toBe(0);
    expect(result.reason).toMatch(/INDEXNOW_KEY/);
  });

  it("submits the sitemap URLs when INDEXNOW_KEY is set", async () => {
    const fakeFetch = vi.fn().mockResolvedValue(
      new Response("", { status: 202, statusText: "Accepted" }),
    );
    const result = await main({
      fetch: fakeFetch,
      env: { INDEXNOW_KEY: "abc123def456" },
      readSitemap: async () => MOCK_SITEMAP_XML,
    });
    expect(fakeFetch).toHaveBeenCalledTimes(1);
    const [url, init] = fakeFetch.mock.calls[0];
    expect(url).toBe(INDEXNOW_ENDPOINT);
    const body = JSON.parse(init.body);
    expect(body.host).toBe("whispaste.de");
    expect(body.key).toBe("abc123def456");
    expect(body.keyLocation).toBe("https://whispaste.de/abc123def456.txt");
    expect(body.urlList).toEqual([
      "https://whispaste.de/",
      "https://whispaste.de/download/",
      "https://whispaste.de/en/",
      "https://whispaste.de/en/download/",
    ]);
    expect(result.skipped).toBe(false);
    expect(result.exitCode).toBe(0);
    expect(result.status).toBe(202);
  });

  it("treats INDEXNOW_DRY_RUN=1 as a dry run (no fetch call) but still validates inputs", async () => {
    const fakeFetch = vi.fn();
    const result = await main({
      fetch: fakeFetch,
      env: { INDEXNOW_KEY: "abc123def456", INDEXNOW_DRY_RUN: "1" },
      readSitemap: async () => MOCK_SITEMAP_XML,
    });
    expect(fakeFetch).not.toHaveBeenCalled();
    expect(result.exitCode).toBe(0);
    expect(result.dryRun).toBe(true);
  });

  it("returns exit code 0 and skipped=false even if the API responds with a non-2xx (logged, not thrown)", async () => {
    // IndexNow returns 4xx when the key is invalid. We log + non-zero exit
    // but never throw — see code comments for rationale.
    const fakeFetch = vi.fn().mockResolvedValue(
      new Response("Invalid key", { status: 403, statusText: "Forbidden" }),
    );
    const result = await main({
      fetch: fakeFetch,
      env: { INDEXNOW_KEY: "bogus" },
      readSitemap: async () => MOCK_SITEMAP_XML,
    });
    expect(result.skipped).toBe(false);
    expect(result.status).toBe(403);
    // Non-2xx still exits non-zero so deploy pipelines surface the problem.
    expect(result.exitCode).toBe(1);
  });

  it("exits with non-zero code when the sitemap cannot be read", async () => {
    const fakeFetch = vi.fn();
    const result = await main({
      fetch: fakeFetch,
      env: { INDEXNOW_KEY: "abc123def456" },
      readSitemap: async () => {
        throw new Error("ENOENT: sitemap missing");
      },
    });
    expect(fakeFetch).not.toHaveBeenCalled();
    expect(result.exitCode).toBe(1);
    expect(result.error).toMatch(/sitemap/i);
  });

  it("exits with non-zero code when the sitemap is empty (no URLs to submit)", async () => {
    const fakeFetch = vi.fn();
    const result = await main({
      fetch: fakeFetch,
      env: { INDEXNOW_KEY: "abc123def456" },
      readSitemap: async () =>
        `<?xml version="1.0"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"></urlset>`,
    });
    expect(fakeFetch).not.toHaveBeenCalled();
    expect(result.exitCode).toBe(1);
    expect(result.error).toMatch(/no URLs/i);
  });

  it("never throws on a network error — returns non-zero exit instead", async () => {
    const fakeFetch = vi
      .fn()
      .mockRejectedValue(new Error("network unreachable"));
    const result = await main({
      fetch: fakeFetch,
      env: { INDEXNOW_KEY: "abc123def456" },
      readSitemap: async () => MOCK_SITEMAP_XML,
    });
    expect(result.exitCode).toBe(1);
    expect(result.error).toMatch(/network unreachable/);
  });
});
