/**
 * Build-time (Node-only) module that translates a GitHub-release-body markdown
 * string into a target language via the OpenAI Chat Completions API while
 * preserving markdown structure (headings, bullets, code-spans, backticks,
 * URLs) across the round-trip.
 *
 * Node-only — DO NOT import from the browser bundle. This module:
 *   - reads `process.env.OPENAI_API_KEY` (never exposed to the client),
 *   - writes to disk under `website/.cache/translations/<sha256>.json` via the
 *     default cache implementation,
 *   - uses `node:fs/promises`, `node:path`, `node:crypto`.
 *
 * Failures are always swallowed: when the API key is missing or any OpenAI
 * call fails (network / 4xx / 5xx / parse), the original English markdown is
 * returned and a `console.warn` is logged. Callers never see an exception.
 *
 * @example
 *   const de = await translateBody({
 *     markdown: "### Highlights\n- did a thing\n",
 *     targetLang: "de",
 *   });
 */
import { createHash } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

/** Async key/value cache abstraction (string → string|null). */
export type TranslationCache = {
  get(key: string): Promise<string | null>;
  set(key: string, value: string): Promise<void>;
};

export type TranslateBodyOptions = {
  /** Source markdown to translate. */
  markdown: string;
  /** Target language code, e.g. `"de"`. */
  targetLang: string;
  /** Source language code. Defaults to `"en"`. */
  sourceLang?: string;
  /** Cache implementation. Defaults to the on-disk file cache. */
  cache?: TranslationCache;
};

/**
 * OpenAI model used for translation. Kept identical to the one used by
 * `scripts/generate-release-notes.ps1` so the tone matches across surfaces.
 */
const OPENAI_MODEL = "gpt-4o-mini";

/** OpenAI Chat Completions endpoint. */
const OPENAI_ENDPOINT = "https://api.openai.com/v1/chat/completions";

/**
 * System prompt — instructs the model to behave as a strict structural
 * translator. Anything that is code-spans, backticks or URLs must round-trip
 * verbatim; only natural-language prose is translated.
 */
const SYSTEM_PROMPT = [
  "You are a technical translator for release notes.",
  "Preserve markdown structure exactly: headings (### …), bullet markers (-, *),",
  "list indentation, blank lines, and the order of items.",
  "Do NOT translate code-spans, content inside backticks, or URLs — keep them verbatim.",
  "Do not add commentary, do not wrap the output in fences, do not change the structure.",
  "Return only the translated markdown.",
].join(" ");

/** Default on-disk cache root: `<website>/.cache/translations/`. */
const DEFAULT_CACHE_DIR = (() => {
  // `scripts/body-translator.ts` → `<website>/scripts/` → `<website>/`.
  const here = dirname(fileURLToPath(import.meta.url));
  return join(here, "..", ".cache", "translations");
})();

/**
 * Translate a release-body markdown string into `targetLang`.
 *
 * Behaviour contract:
 *   - Cache lookup first; on hit, returns cached value without calling OpenAI.
 *   - On cache miss, calls OpenAI and (on success) writes to the cache.
 *   - On missing `OPENAI_API_KEY`, returns the original markdown and warns.
 *   - On any OpenAI failure (network / non-2xx / parse), returns the original
 *     markdown and warns. Never throws.
 */
export async function translateBody(
  options: TranslateBodyOptions,
): Promise<string> {
  const { markdown, targetLang, sourceLang = "en" } = options;
  const cache = options.cache ?? createFileCache();

  const key = cacheKey(targetLang, markdown);

  // Cache hit short-circuits the entire pipeline — no env read, no API call.
  const cached = await cache.get(key);
  if (cached !== null) {
    return cached;
  }

  // Read the API key lazily so that a cache hit never depends on env state.
  // We read it via `process.env` directly (never imported, never bundled).
  const apiKey = process.env["OPENAI_API_KEY"];
  if (!apiKey || apiKey.length === 0) {
    console.warn(
      "[body-translator] OPENAI_API_KEY is not set — returning original markdown without translation.",
    );
    return markdown;
  }

  let translated: string;
  try {
    translated = await callOpenAI({ apiKey, markdown, targetLang, sourceLang });
  } catch (err) {
    console.warn(
      `[body-translator] OpenAI request failed (${(err as Error).message}) — returning original markdown.`,
    );
    return markdown;
  }

  // Best-effort cache write. A cache-write failure must not change the return
  // value — translation already succeeded — so we warn and move on.
  try {
    await cache.set(key, translated);
  } catch (err) {
    console.warn(
      `[body-translator] Cache write failed (${(err as Error).message}) — translation succeeded but was not cached.`,
    );
  }

  return translated;
}

/** Build the deterministic cache key for a `(targetLang, markdown)` pair. */
function cacheKey(targetLang: string, markdown: string): string {
  return createHash("sha256").update(`${targetLang}:${markdown}`).digest("hex");
}

type OpenAIRequest = {
  apiKey: string;
  markdown: string;
  targetLang: string;
  sourceLang: string;
};

/**
 * POST to the OpenAI Chat Completions endpoint and return the assistant's
 * message content. Throws on any non-2xx response or unexpected payload shape
 * — the caller (`translateBody`) converts every throw into a warn-and-return-
 * original.
 */
async function callOpenAI(req: OpenAIRequest): Promise<string> {
  const body = JSON.stringify({
    model: OPENAI_MODEL,
    messages: [
      { role: "system", content: SYSTEM_PROMPT },
      {
        role: "user",
        content: [
          `Translate the following markdown from ${req.sourceLang} to ${req.targetLang}.`,
          "Preserve all markdown structure exactly. Do not translate code, backticks, or URLs.",
          "",
          req.markdown,
        ].join("\n"),
      },
    ],
    temperature: 0.2,
  });

  const response = await fetch(OPENAI_ENDPOINT, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${req.apiKey}`,
    },
    body,
  });

  if (!response.ok) {
    throw new Error(`OpenAI HTTP ${response.status}`);
  }

  const payload: unknown = await response.json();
  const content = extractContent(payload);
  if (content === null) {
    throw new Error("OpenAI response shape unexpected (missing choices[0].message.content)");
  }
  return content;
}

/** Narrow an unknown OpenAI payload to the single string we need. */
function extractContent(payload: unknown): string | null {
  if (typeof payload !== "object" || payload === null) return null;
  const choices = (payload as { choices?: unknown }).choices;
  if (!Array.isArray(choices) || choices.length === 0) return null;
  const first = choices[0];
  if (typeof first !== "object" || first === null) return null;
  const message = (first as { message?: unknown }).message;
  if (typeof message !== "object" || message === null) return null;
  const content = (message as { content?: unknown }).content;
  return typeof content === "string" ? content : null;
}

/**
 * Default on-disk cache. Stores one JSON file per key under
 * `website/.cache/translations/<sha256>.json`. The directory is created on
 * first write.
 */
export function createFileCache(rootDir: string = DEFAULT_CACHE_DIR): TranslationCache {
  return {
    async get(key: string): Promise<string | null> {
      const path = join(rootDir, `${key}.json`);
      try {
        const raw = await readFile(path, "utf8");
        const parsed: unknown = JSON.parse(raw);
        if (
          typeof parsed === "object" &&
          parsed !== null &&
          typeof (parsed as { value?: unknown }).value === "string"
        ) {
          return (parsed as { value: string }).value;
        }
        return null;
      } catch {
        // ENOENT / parse errors / permission errors all degrade to a cache miss.
        return null;
      }
    },
    async set(key: string, value: string): Promise<void> {
      await mkdir(rootDir, { recursive: true });
      const path = join(rootDir, `${key}.json`);
      await writeFile(path, JSON.stringify({ key, value }), "utf8");
    },
  };
}
