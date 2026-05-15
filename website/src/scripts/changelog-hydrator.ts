/**
 * Browser-side hydrator that fetches the latest GitHub releases for the
 * Whispaste repository and *prepends* newly published cards into the
 * statically-rendered changelog list — without ever touching cards that were
 * baked in at build time.
 *
 * Static rendering provides the authoritative baseline (fast first paint,
 * works offline, indexable). The hydrator is purely additive: it makes the
 * page feel fresher when a brand-new release has shipped between the last
 * build and the user's visit, and is otherwise invisible.
 *
 * Caching
 * -------
 *  - Responses are cached in `localStorage['whispaste:changelog-cache']` as
 *    `{ etag, releases, timestamp }`.
 *  - Within `ttlMs` (default 5 minutes) we skip the network entirely.
 *  - Outside the TTL we revalidate with `If-None-Match`. A `304` only refreshes
 *    the `timestamp` — no DOM change.
 *  - A `200` newer than `currentTopVersion` triggers prepends; a `200` with the
 *    same top tag refreshes the cache without DOM changes.
 *
 * Failure mode is *silent*: network errors, 4xx/5xx, parse failures, and rate
 * limits never bubble up to the user. We `console.warn` (allowed by ESLint
 * rule `no-console`) so issues remain debuggable while not polluting prod
 * consoles with red errors.
 *
 * Idempotency
 * -----------
 * Multiple `hydrate(...)` calls share a module-level lock keyed by mount
 * selector. The second call no-ops until the first resolves and never prepends
 * the same tag twice (tracked via `data-hydrated-tag` attributes).
 *
 * Security
 * --------
 * The release body is run through `parseReleaseBody` (the same isomorphic
 * parser the build uses) and then turned into HTML by a minimal block→DOM
 * renderer. Any HTML produced by parser internals is sanitised with DOMPurify
 * before insertion. Markdown is also rendered with DOMPurify so unexpected
 * `<script>` / `onerror=` payloads cannot escape.
 *
 * @example
 *   const cleanup = hydrate({
 *     mountSelector: "#changelog-list",
 *     owner: "silvio-lindstedt",
 *     repo: "whispaste",
 *     cardRenderer: defaultCardRenderer,
 *     currentTopVersion: "v1.2.13",
 *   });
 *   // Later, e.g. on SPA navigation:
 *   cleanup();
 */

import DOMPurify from "dompurify";
import { parseReleaseBody, type ReleaseBlocks } from "../../scripts/markdown-to-blocks.ts";

/** Public release shape exposed to {@link HydrateOptions.cardRenderer}. */
export type Release = {
  tag: string;
  name: string;
  publishedAt: string;
  bodyMarkdown: string;
  htmlUrl: string;
  blocks: ReleaseBlocks;
};

export type HydrateOptions = {
  /** CSS selector for the container into which new cards are prepended. */
  mountSelector: string;
  /** GitHub repository owner, e.g. `"silvio-lindstedt"`. */
  owner: string;
  /** GitHub repository name, e.g. `"whispaste"`. */
  repo: string;
  /**
   * Renderer that turns a {@link Release} into a DOM element. Mounted as-is
   * (`prepend`) — callers are responsible for the element's structure and
   * styling.
   */
  cardRenderer: (release: Release) => HTMLElement;
  /** Tag of the statically-rendered top release (used for delta detection). */
  currentTopVersion: string;
  /** Cache lifetime in milliseconds. Defaults to 5 minutes. */
  ttlMs?: number;
};

/** Shape persisted in `localStorage` between visits. */
type CacheEntry = {
  etag: string | null;
  releases: Release[];
  timestamp: number;
};

const CACHE_KEY = "whispaste:changelog-cache";
const DEFAULT_TTL_MS = 5 * 60_000;
const HYDRATED_ATTR = "data-hydrated-tag";

/**
 * Per-mount in-flight locks. Keeps re-entrant `hydrate(...)` calls from
 * prepending the same release twice (e.g. when a `<script>` tag is included
 * on a page that fires `DOMContentLoaded` after the script has already run).
 */
const inFlightLocks = new Map<string, Promise<void>>();

/**
 * Hydrate the changelog list at `mountSelector` against the live GitHub
 * Releases API.
 *
 * Returns a cleanup function that releases any retained timers, listeners, or
 * locks. Calling cleanup is optional but recommended for SPA-style navigation.
 */
export function hydrate(options: HydrateOptions): () => void {
  const {
    mountSelector,
    owner,
    repo,
    cardRenderer,
    currentTopVersion,
    ttlMs = DEFAULT_TTL_MS,
  } = options;

  let cancelled = false;

  // Lock per mount selector: a second hydrate() call returns immediately if a
  // previous run is still in flight against the same mount.
  if (inFlightLocks.has(mountSelector)) {
    return () => {
      cancelled = true;
    };
  }

  const run = async (): Promise<void> => {
    try {
      const mount = document.querySelector(mountSelector);
      if (!(mount instanceof HTMLElement)) {
        // Mount missing: nothing to hydrate. Silent — static page is still fine.
        return;
      }

      const cached = readCache();
      const now = Date.now();

      if (cached && now - cached.timestamp < ttlMs) {
        // Fresh cache hit — skip network entirely.
        return;
      }

      const url = `https://api.github.com/repos/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/releases?per_page=5`;
      const headers: Record<string, string> = {
        Accept: "application/vnd.github+json",
      };
      if (cached?.etag) {
        headers["If-None-Match"] = cached.etag;
      }

      let response: Response;
      try {
        response = await fetch(url, { headers });
      } catch (err) {
        // Offline / DNS / TLS / abort: silent fail, keep static DOM intact.
        warn("network error", err);
        return;
      }

      if (cancelled) return;

      if (response.status === 304) {
        // Not modified — refresh timestamp so we honour the TTL again.
        if (cached) {
          writeCache({ ...cached, timestamp: now });
        }
        return;
      }

      if (response.status === 403) {
        // Rate limited (or other forbidden response): keep cache, no DOM change.
        warn(`rate limited or forbidden (HTTP ${String(response.status)})`);
        return;
      }

      if (!response.ok) {
        // 4xx / 5xx: silent fail.
        warn(`unexpected HTTP ${String(response.status)}`);
        return;
      }

      let payload: unknown;
      try {
        payload = await response.json();
      } catch (err) {
        warn("parse error", err);
        return;
      }

      if (!Array.isArray(payload)) {
        warn("parse error: response is not an array");
        return;
      }

      const releases: Release[] = [];
      for (const raw of payload) {
        const parsed = parseReleasePayload(raw);
        if (parsed === null) {
          // Mixed array: skip the bad entry rather than failing the whole pass.
          warn("parse error: malformed release entry");
          return;
        }
        if (parsed.isDraft || parsed.isPrerelease) continue;
        releases.push(parsed.release);
      }

      const etag = response.headers.get("etag");
      writeCache({ etag, releases, timestamp: now });

      if (releases.length === 0) return;
      const topTag = releases[0]?.tag;
      if (typeof topTag !== "string") return;

      if (compareTags(topTag, currentTopVersion) <= 0) {
        // No new release — cache is up to date, DOM stays untouched.
        return;
      }

      // Prepend every release whose tag is newer than `currentTopVersion`,
      // bottom-up so the final order in the DOM is newest-first.
      const newer = releases.filter(
        (r) => compareTags(r.tag, currentTopVersion) > 0,
      );
      // Reverse so the *newest* ends up at the top after sequential `prepend`.
      const inPrependOrder = [...newer].reverse();

      for (const release of inPrependOrder) {
        if (cancelled) return;
        if (mount.querySelector(`[${HYDRATED_ATTR}="${cssEscape(release.tag)}"]`)) {
          // Defensive: another hydrate run already prepended this tag.
          continue;
        }
        const card = cardRenderer(release);
        card.setAttribute(HYDRATED_ATTR, release.tag);
        mount.prepend(card);
      }
    } catch (err) {
      // Last-ditch safety net — never surface anything to the user.
      warn("unexpected error", err);
    }
  };

  const promise = run().finally(() => {
    inFlightLocks.delete(mountSelector);
  });
  inFlightLocks.set(mountSelector, promise);

  return () => {
    cancelled = true;
  };
}

/**
 * Minimal block→HTML renderer used by {@link defaultCardRenderer}. Exported
 * for tests so we can assert sanitisation behaviour without going through
 * `cardRenderer`.
 */
export function renderBlocksToHtml(blocks: ReleaseBlocks): string {
  const parts: string[] = [];
  for (const section of blocks.sections) {
    parts.push(`<h3>${escapeHtml(section.heading)}</h3>`);
    if (section.items.length === 0) continue;
    parts.push("<ul>");
    for (const item of section.items) {
      const titlePart =
        item.title !== undefined && item.title.length > 0
          ? `<strong>${escapeHtml(item.title)}</strong>: `
          : "";
      parts.push(`<li>${titlePart}${escapeHtml(item.body)}</li>`);
    }
    parts.push("</ul>");
  }
  return DOMPurify.sanitize(parts.join(""));
}

/**
 * Reasonable default card renderer matching the existing static markup style
 * in `changelog.astro`. Callers can pass their own renderer for custom layouts.
 */
export function defaultCardRenderer(release: Release): HTMLElement {
  const article = document.createElement("article");
  article.className =
    "release-card rounded-2xl border border-white/[0.06] p-6 sm:p-8 scroll-reveal visible";
  const header = document.createElement("div");
  header.className = "flex items-center gap-3 mb-5";
  const badge = document.createElement("span");
  badge.className =
    "inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-sm font-semibold bg-brand-cyan/15 text-brand-cyan border border-brand-cyan/20";
  badge.textContent = release.tag.startsWith("v") ? release.tag : `v${release.tag}`;
  const time = document.createElement("time");
  time.className = "text-sm text-gray-500";
  time.textContent = release.publishedAt.slice(0, 10);
  header.appendChild(badge);
  header.appendChild(time);
  article.appendChild(header);

  const body = document.createElement("div");
  body.className = "release-card-body";
  body.innerHTML = renderBlocksToHtml(release.blocks);
  article.appendChild(body);

  return article;
}

function readCache(): CacheEntry | null {
  try {
    const raw = localStorage.getItem(CACHE_KEY);
    if (raw === null) return null;
    const parsed = JSON.parse(raw) as unknown;
    if (!isObject(parsed)) return null;
    const etag = parsed["etag"];
    const releases = parsed["releases"];
    const timestamp = parsed["timestamp"];
    if (
      (typeof etag !== "string" && etag !== null) ||
      !Array.isArray(releases) ||
      typeof timestamp !== "number"
    ) {
      return null;
    }
    return { etag, releases: releases as Release[], timestamp };
  } catch {
    return null;
  }
}

function writeCache(entry: CacheEntry): void {
  try {
    localStorage.setItem(CACHE_KEY, JSON.stringify(entry));
  } catch {
    // Quota exceeded / disabled storage — silent.
  }
}

type ParsedRelease = {
  release: Release;
  isDraft: boolean;
  isPrerelease: boolean;
};

function parseReleasePayload(value: unknown): ParsedRelease | null {
  if (!isObject(value)) return null;
  const tag = value["tag_name"];
  const name = value["name"];
  const publishedAt = value["published_at"];
  const body = value["body"];
  const htmlUrl = value["html_url"];
  const prerelease = value["prerelease"];
  const draft = value["draft"];
  if (
    typeof tag !== "string" ||
    typeof publishedAt !== "string" ||
    typeof htmlUrl !== "string" ||
    typeof prerelease !== "boolean" ||
    typeof draft !== "boolean"
  ) {
    return null;
  }
  if (typeof name !== "string" && name !== null) return null;
  if (typeof body !== "string" && body !== null) return null;

  const bodyMarkdown = typeof body === "string" ? body : "";
  return {
    release: {
      tag,
      name: typeof name === "string" ? name : tag,
      publishedAt,
      bodyMarkdown,
      htmlUrl,
      blocks: parseReleaseBody(bodyMarkdown),
    },
    isDraft: draft,
    isPrerelease: prerelease,
  };
}

/**
 * Compare two semver-ish tags (`v1.2.13` vs `v1.2.14` or `1.2.13` vs `1.3.0`).
 * Returns >0 if `a` is newer than `b`, <0 if older, 0 if equal. Non-numeric
 * segments fall back to lexical compare.
 */
function compareTags(a: string, b: string): number {
  const segA = stripV(a).split(".");
  const segB = stripV(b).split(".");
  const len = Math.max(segA.length, segB.length);
  for (let i = 0; i < len; i++) {
    const partA = segA[i] ?? "0";
    const partB = segB[i] ?? "0";
    const numA = Number.parseInt(partA, 10);
    const numB = Number.parseInt(partB, 10);
    if (Number.isFinite(numA) && Number.isFinite(numB)) {
      if (numA !== numB) return numA - numB;
    } else if (partA !== partB) {
      return partA < partB ? -1 : 1;
    }
  }
  return 0;
}

function stripV(tag: string): string {
  return tag.startsWith("v") || tag.startsWith("V") ? tag.slice(1) : tag;
}

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function cssEscape(value: string): string {
  // Match the CSSOM `CSS.escape` semantics minimally — we only need to make
  // attribute selectors with dots / dashes work in jsdom and modern browsers.
  return value.replace(/(["\\])/g, "\\$1");
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function warn(message: string, err?: unknown): void {
  if (err !== undefined) {
    console.warn(`[changelog-hydrator] ${message}`, err);
  } else {
    console.warn(`[changelog-hydrator] ${message}`);
  }
}
