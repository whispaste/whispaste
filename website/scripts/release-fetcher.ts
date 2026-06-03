/**
 * Build-time module that fetches the most recent GitHub releases for a
 * repository and returns them as typed {@link Release} objects.
 *
 * This module is consumed during the Astro build (see issue 07 for wiring) to
 * source the website's changelog directly from the GitHub Releases API — the
 * single source of truth. The function is pure over its inputs: no disk-IO,
 * no module-level mutable state, no caching. Callers handle fallback by
 * catching {@link ReleaseFetcherError} and branching on its categorised
 * `cause`.
 *
 * Network access uses Node 22's built-in `fetch` (no external dependency).
 *
 * @example
 *   const releases = await fetchReleases({
 *     owner: "silvio-lindstedt",
 *     repo: "whispaste",
 *     count: 5,
 *     token: process.env.GITHUB_TOKEN,
 *   });
 */

/** A single released, non-draft, non-prerelease GitHub release. */
export type Release = {
  tag: string;
  name: string;
  publishedAt: string;
  bodyMarkdown: string;
  htmlUrl: string;
  isPrerelease: boolean;
  isDraft: boolean;
  /**
   * German release body, sourced from the release's `release-notes-de.md`
   * asset (the single source of truth produced by
   * `scripts/generate-release-notes.mjs` and attached in `release.yml`).
   * `null` when the release carries no such asset — there is deliberately no
   * translation fallback.
   */
  deBodyMarkdown: string | null;
};

/** Asset filename carrying the German release notes (attached by `release.yml`). */
const DE_NOTES_ASSET = "release-notes-de.md";

/** Categorised failure modes that callers can branch on for fallback logic. */
export type ReleaseFetcherCause = "network" | "rate-limited" | "auth" | "parse";

/**
 * Error thrown by {@link fetchReleases} when the request fails for any
 * reason. The {@link cause} field distinguishes recoverable conditions
 * (`rate-limited`, `network`) from configuration errors (`auth`) and
 * malformed responses (`parse`).
 */
export class ReleaseFetcherError extends Error {
  public readonly cause: ReleaseFetcherCause;

  constructor(cause: ReleaseFetcherCause, message: string, options?: { cause?: unknown }) {
    super(message);
    this.name = "ReleaseFetcherError";
    this.cause = cause;
    if (options?.cause !== undefined) {
      // Preserve the underlying error chain for debugging while keeping the
      // categorised string on the public `cause` field.
      Object.defineProperty(this, "originalCause", {
        value: options.cause,
        enumerable: false,
      });
    }
  }
}

export type FetchReleasesOptions = {
  owner: string;
  repo: string;
  /** Maximum number of releases to return after filtering. Defaults to 5. */
  count?: number;
  /** Optional GitHub token. When set, sent as `Authorization: Bearer <token>`. */
  token?: string;
};

const GITHUB_API_BASE = "https://api.github.com";

/**
 * Fetch the most recent published releases for `{owner}/{repo}`.
 *
 * Filters out drafts and prereleases **before** applying the `count` cut so
 * that the returned list contains exactly the requested number of
 * user-visible releases (up to availability).
 */
export async function fetchReleases(
  options: FetchReleasesOptions,
): Promise<Release[]> {
  const { owner, repo, count = 5, token } = options;

  // The GitHub Releases endpoint supports `per_page` up to 100. We request
  // enough to absorb a reasonable number of leading drafts/prereleases while
  // still bounding the response size.
  const perPage = Math.min(100, Math.max(count * 2, count + 10));
  const url = `${GITHUB_API_BASE}/repos/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/releases?per_page=${perPage}`;

  const headers: Record<string, string> = {
    Accept: "application/vnd.github+json",
    "X-GitHub-Api-Version": "2022-11-28",
  };
  if (token) {
    headers["Authorization"] = `Bearer ${token}`;
  }

  let response: Response;
  try {
    response = await fetch(url, { headers });
  } catch (err) {
    throw new ReleaseFetcherError(
      "network",
      `Network error while fetching releases for ${owner}/${repo}: ${(err as Error).message}`,
      { cause: err },
    );
  }

  if (!response.ok) {
    if (response.status === 401) {
      throw new ReleaseFetcherError(
        "auth",
        `GitHub API rejected credentials (HTTP 401) for ${owner}/${repo}.`,
      );
    }
    if (response.status === 403 && isRateLimited(response)) {
      throw new ReleaseFetcherError(
        "rate-limited",
        `GitHub API rate limit exceeded (HTTP 403) for ${owner}/${repo}.`,
      );
    }
    throw new ReleaseFetcherError(
      "network",
      `GitHub API returned HTTP ${response.status} for ${owner}/${repo}.`,
    );
  }

  let payload: unknown;
  try {
    payload = await response.json();
  } catch (err) {
    throw new ReleaseFetcherError(
      "parse",
      `Failed to parse JSON response from GitHub API for ${owner}/${repo}: ${(err as Error).message}`,
      { cause: err },
    );
  }

  if (!Array.isArray(payload)) {
    throw new ReleaseFetcherError(
      "parse",
      `Unexpected response shape from GitHub API for ${owner}/${repo}: expected array.`,
    );
  }

  const releases: Release[] = [];
  const deAssetUrls: (string | null)[] = [];
  for (const raw of payload) {
    if (!isReleasePayload(raw)) {
      throw new ReleaseFetcherError(
        "parse",
        `Unexpected release entry shape from GitHub API for ${owner}/${repo}.`,
      );
    }
    if (raw.draft || raw.prerelease) continue;
    const deAsset = (raw.assets ?? []).find((a) => a.name === DE_NOTES_ASSET);
    releases.push({
      tag: raw.tag_name,
      name: raw.name ?? raw.tag_name,
      publishedAt: raw.published_at,
      bodyMarkdown: raw.body ?? "",
      htmlUrl: raw.html_url,
      isPrerelease: raw.prerelease,
      isDraft: raw.draft,
      deBodyMarkdown: null,
    });
    deAssetUrls.push(deAsset?.browser_download_url ?? null);
    if (releases.length >= count) break;
  }

  // Resolve the German body for each release from its `release-notes-de.md`
  // asset. Best-effort: a missing or unreachable asset leaves `deBodyMarkdown`
  // null (English-only) — there is no translation fallback by design.
  await Promise.all(
    releases.map(async (release, i) => {
      const assetUrl = deAssetUrls[i];
      if (assetUrl) {
        release.deBodyMarkdown = await fetchAssetText(assetUrl, token);
      }
    }),
  );

  return releases;
}

/**
 * Fetch the UTF-8 text of a release asset. Returns `null` on any failure
 * (non-OK status, network error) so a missing German asset degrades the entry
 * to English-only rather than failing the whole build.
 */
async function fetchAssetText(
  url: string,
  token?: string,
): Promise<string | null> {
  const headers: Record<string, string> = { Accept: "application/octet-stream" };
  if (token) headers["Authorization"] = `Bearer ${token}`;
  try {
    const res = await fetch(url, { headers });
    if (!res.ok) return null;
    const text = await res.text();
    return text.length > 0 ? text : null;
  } catch {
    return null;
  }
}

function isRateLimited(response: Response): boolean {
  // GitHub signals primary rate limiting with X-RateLimit-Remaining: 0 (the
  // most reliable marker). Secondary rate limits set Retry-After instead.
  const remaining = response.headers.get("X-RateLimit-Remaining");
  if (remaining !== null && Number(remaining) === 0) return true;
  if (response.headers.has("Retry-After")) return true;
  return false;
}

type GitHubReleaseAsset = {
  name: string;
  browser_download_url: string;
};

type GitHubReleasePayload = {
  tag_name: string;
  name: string | null;
  published_at: string;
  body: string | null;
  html_url: string;
  prerelease: boolean;
  draft: boolean;
  assets?: GitHubReleaseAsset[];
};

function isReleaseAsset(value: unknown): value is GitHubReleaseAsset {
  if (typeof value !== "object" || value === null) return false;
  const v = value as Record<string, unknown>;
  return (
    typeof v.name === "string" && typeof v.browser_download_url === "string"
  );
}

function isReleasePayload(value: unknown): value is GitHubReleasePayload {
  if (typeof value !== "object" || value === null) return false;
  const v = value as Record<string, unknown>;
  return (
    typeof v.tag_name === "string" &&
    (typeof v.name === "string" || v.name === null) &&
    typeof v.published_at === "string" &&
    (typeof v.body === "string" || v.body === null) &&
    typeof v.html_url === "string" &&
    typeof v.prerelease === "boolean" &&
    typeof v.draft === "boolean" &&
    // GitHub always returns an `assets` array (possibly empty); tolerate its
    // absence for hand-built fixtures, but reject a non-array if present.
    (v.assets === undefined ||
      (Array.isArray(v.assets) && v.assets.every(isReleaseAsset)))
  );
}
