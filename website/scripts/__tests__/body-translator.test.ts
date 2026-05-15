/**
 * Tests for {@link translateBody} and {@link createFileCache}.
 *
 * The public surface is the `translateBody` Promise-returning function plus
 * the on-disk `createFileCache` helper. All OpenAI calls are stubbed via
 * `vi.fn()` substituting `globalThis.fetch` — no real network IO.
 *
 * Each test isolates `process.env.OPENAI_API_KEY` so that the missing-key
 * branch can be exercised without leaking state into the rest of the suite.
 */
import { mkdtemp, readdir, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  afterEach,
  beforeEach,
  describe,
  expect,
  it,
  vi,
  type Mock,
} from "vitest";
import {
  createFileCache,
  translateBody,
  type TranslationCache,
} from "../body-translator.ts";

function jsonResponse(body: unknown, init: ResponseInit = {}): Response {
  return new Response(JSON.stringify(body), {
    status: 200,
    headers: { "Content-Type": "application/json" },
    ...init,
  });
}

/** Build a well-formed OpenAI Chat Completions response with `content`. */
function openAIResponse(content: string): Response {
  return jsonResponse({
    id: "chatcmpl-test",
    object: "chat.completion",
    choices: [
      {
        index: 0,
        message: { role: "assistant", content },
        finish_reason: "stop",
      },
    ],
  });
}

/** Minimal in-memory cache used by most tests. */
function createMemoryCache(): TranslationCache & { store: Map<string, string> } {
  const store = new Map<string, string>();
  return {
    store,
    async get(key: string): Promise<string | null> {
      return store.has(key) ? (store.get(key) ?? null) : null;
    },
    async set(key: string, value: string): Promise<void> {
      store.set(key, value);
    },
  };
}

let fetchMock: Mock;
let originalApiKey: string | undefined;

beforeEach(() => {
  fetchMock = vi.fn();
  vi.stubGlobal("fetch", fetchMock);
  originalApiKey = process.env["OPENAI_API_KEY"];
  process.env["OPENAI_API_KEY"] = "test-key-must-not-leak";
  // Silence the expected console.warn output during fallback paths so the
  // test log stays readable. Tests assert on `.mock.calls` directly.
  vi.spyOn(console, "warn").mockImplementation(() => {});
});

afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
  if (originalApiKey === undefined) {
    delete process.env["OPENAI_API_KEY"];
  } else {
    process.env["OPENAI_API_KEY"] = originalApiKey;
  }
});

describe("translateBody — happy path", () => {
  it("translates EN markdown to DE via the (mocked) OpenAI client", async () => {
    fetchMock.mockResolvedValue(
      openAIResponse("### Highlights\n- etwas Neues\n"),
    );
    const cache = createMemoryCache();

    const out = await translateBody({
      markdown: "### Highlights\n- something new\n",
      targetLang: "de",
      cache,
    });

    expect(out).toBe("### Highlights\n- etwas Neues\n");
    expect(fetchMock).toHaveBeenCalledTimes(1);
    const [url, init] = fetchMock.mock.calls[0] as [string, RequestInit];
    expect(url).toBe("https://api.openai.com/v1/chat/completions");
    const headers = new Headers(init.headers);
    expect(headers.get("Authorization")).toBe("Bearer test-key-must-not-leak");
    expect(headers.get("Content-Type")).toBe("application/json");
    // The request body must reference gpt-4o-mini (parity with the PS script).
    expect(typeof init.body).toBe("string");
    expect(init.body as string).toContain("gpt-4o-mini");
  });
});

describe("translateBody — cache behaviour", () => {
  it("does not call OpenAI on a cache hit for identical (targetLang, body)", async () => {
    fetchMock.mockResolvedValue(openAIResponse("### Highlights\n- cached\n"));
    const cache = createMemoryCache();

    const markdown = "### Highlights\n- something\n";
    const first = await translateBody({ markdown, targetLang: "de", cache });
    const second = await translateBody({ markdown, targetLang: "de", cache });

    expect(first).toBe("### Highlights\n- cached\n");
    expect(second).toBe(first);
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it("calls OpenAI again when the body changes (cache miss)", async () => {
    fetchMock
      .mockResolvedValueOnce(openAIResponse("erste Übersetzung"))
      .mockResolvedValueOnce(openAIResponse("zweite Übersetzung"));
    const cache = createMemoryCache();

    const first = await translateBody({
      markdown: "first body",
      targetLang: "de",
      cache,
    });
    const second = await translateBody({
      markdown: "second body — different",
      targetLang: "de",
      cache,
    });

    expect(first).toBe("erste Übersetzung");
    expect(second).toBe("zweite Übersetzung");
    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(cache.store.size).toBe(2);
  });
});

describe("translateBody — failure fallbacks", () => {
  it("returns the original markdown and warns when fetch rejects (network error)", async () => {
    fetchMock.mockRejectedValue(new Error("ECONNRESET"));
    const cache = createMemoryCache();
    const original = "### Highlights\n- thing\n";

    const out = await translateBody({
      markdown: original,
      targetLang: "de",
      cache,
    });

    expect(out).toBe(original);
    expect(console.warn).toHaveBeenCalledTimes(1);
    // Failure path must NOT poison the cache with the original.
    expect(cache.store.size).toBe(0);
  });

  it("returns the original markdown and warns on HTTP 500", async () => {
    fetchMock.mockResolvedValue(
      new Response("server error", { status: 500 }),
    );
    const cache = createMemoryCache();
    const original = "### Highlights\n- thing\n";

    const out = await translateBody({
      markdown: original,
      targetLang: "de",
      cache,
    });

    expect(out).toBe(original);
    expect(console.warn).toHaveBeenCalledTimes(1);
  });

  it("returns the original markdown and warns on HTTP 401 (auth)", async () => {
    fetchMock.mockResolvedValue(
      new Response("Unauthorized", { status: 401 }),
    );
    const cache = createMemoryCache();
    const original = "### Highlights\n- thing\n";

    const out = await translateBody({
      markdown: original,
      targetLang: "de",
      cache,
    });

    expect(out).toBe(original);
    expect(console.warn).toHaveBeenCalledTimes(1);
  });

  it("returns the original markdown and warns when OPENAI_API_KEY is missing — no API call made", async () => {
    delete process.env["OPENAI_API_KEY"];
    const cache = createMemoryCache();
    const original = "### Highlights\n- thing\n";

    const out = await translateBody({
      markdown: original,
      targetLang: "de",
      cache,
    });

    expect(out).toBe(original);
    expect(fetchMock).not.toHaveBeenCalled();
    expect(console.warn).toHaveBeenCalledTimes(1);
  });

  it("returns the original markdown and warns when OPENAI_API_KEY is an empty string", async () => {
    process.env["OPENAI_API_KEY"] = "";
    const cache = createMemoryCache();
    const original = "### Highlights\n- thing\n";

    const out = await translateBody({
      markdown: original,
      targetLang: "de",
      cache,
    });

    expect(out).toBe(original);
    expect(fetchMock).not.toHaveBeenCalled();
    expect(console.warn).toHaveBeenCalledTimes(1);
  });

  it("returns the original markdown and warns on an unexpected response shape (parse-like failure)", async () => {
    fetchMock.mockResolvedValue(jsonResponse({ unexpected: "shape" }));
    const cache = createMemoryCache();
    const original = "### Highlights\n- thing\n";

    const out = await translateBody({
      markdown: original,
      targetLang: "de",
      cache,
    });

    expect(out).toBe(original);
    expect(console.warn).toHaveBeenCalledTimes(1);
  });
});

describe("translateBody — markdown structure preservation (smoke)", () => {
  it("round-trips headings, bullets, code-spans, backticks and URLs when the model echoes input", async () => {
    const input = [
      "### Highlights",
      "- Updated the `whisper-server` binary",
      "- See https://example.com/changelog for details",
      "",
      "### Bug Fixes",
      "- Fixed `RecordingTriggerHandler` lifetime",
      "",
    ].join("\n");
    // Identity response: the model returns exactly what was sent.
    fetchMock.mockResolvedValue(openAIResponse(input));
    const cache = createMemoryCache();

    const out = await translateBody({
      markdown: input,
      targetLang: "de",
      cache,
    });

    expect(out).toBe(input);
    // Cross-check the load-bearing structural tokens explicitly so that a
    // future refactor that strips them fails this test loudly.
    expect(out).toContain("### Highlights");
    expect(out).toContain("### Bug Fixes");
    expect(out).toContain("- Updated the `whisper-server` binary");
    expect(out).toContain("https://example.com/changelog");
    expect(out).toContain("`RecordingTriggerHandler`");
  });
});

describe("createFileCache — default on-disk cache", () => {
  let tmpRoot: string;

  beforeEach(async () => {
    tmpRoot = await mkdtemp(join(tmpdir(), "body-translator-cache-"));
  });

  afterEach(async () => {
    await rm(tmpRoot, { recursive: true, force: true });
  });

  it("writes one JSON file per cache key under the configured root", async () => {
    fetchMock.mockResolvedValue(openAIResponse("### Übersicht\n- etwas\n"));
    const cache = createFileCache(tmpRoot);

    const out = await translateBody({
      markdown: "### Highlights\n- something\n",
      targetLang: "de",
      cache,
    });
    expect(out).toBe("### Übersicht\n- etwas\n");

    const entries = await readdir(tmpRoot);
    expect(entries).toHaveLength(1);
    const file = entries[0] as string;
    expect(file).toMatch(/^[0-9a-f]{64}\.json$/);

    const onDisk = JSON.parse(
      await readFile(join(tmpRoot, file), "utf8"),
    ) as { key: string; value: string };
    expect(onDisk.value).toBe("### Übersicht\n- etwas\n");
    expect(onDisk.key).toMatch(/^[0-9a-f]{64}$/);

    // Second call with identical input must NOT trigger another fetch — the
    // file we just wrote is read back instead.
    fetchMock.mockClear();
    const cache2 = createFileCache(tmpRoot);
    const second = await translateBody({
      markdown: "### Highlights\n- something\n",
      targetLang: "de",
      cache: cache2,
    });
    expect(second).toBe("### Übersicht\n- etwas\n");
    expect(fetchMock).not.toHaveBeenCalled();
  });
});
