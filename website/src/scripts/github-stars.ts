/**
 * Stargazer count of the public repository, resolved on the server at build
 * time (and once per dev-server process). Visitors' browsers never contact
 * GitHub, so no visitor IP leaves the site.
 *
 * The count must never vanish because of the API's anonymous 60 requests/hour
 * limit (shared CI runner IPs exhaust it routinely), so it resolves in layers:
 *   1. a fresh disk cache (< CACHE_TTL) answers without any request;
 *   2. otherwise the API is asked, with GITHUB_TOKEN when set (CI passes the
 *      workflow token: 5,000 requests/hour), and a hit refreshes the cache;
 *   3. on any failure the last cached value is used, however old;
 *   4. without a cache the committed last-known value in
 *      src/data/github-stars.json is the floor.
 * The token is only ever sent to api.github.com.
 */
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import process from 'node:process';
import seed from '../data/github-stars.json';

const REPO_API = 'https://api.github.com/repos/whispaste/whispaste';
const CACHE_TTL = 6 * 60 * 60 * 1000;

type Snapshot = { count: number; fetchedAt: string };

const isSnapshot = (value: unknown): value is Snapshot =>
  typeof value === 'object' &&
  value !== null &&
  typeof (value as Snapshot).count === 'number' &&
  (value as Snapshot).count > 0 &&
  typeof (value as Snapshot).fetchedAt === 'string';

const defaultCacheFile = () => join(process.cwd(), 'node_modules', '.cache', 'whispaste', 'github-stars.json');

function readCache(file: string): Snapshot | null {
  try {
    const value: unknown = JSON.parse(readFileSync(file, 'utf8'));
    return isSnapshot(value) ? value : null;
  } catch {
    return null;
  }
}

function writeCache(file: string, snapshot: Snapshot): void {
  try {
    mkdirSync(dirname(file), { recursive: true });
    writeFileSync(file, JSON.stringify(snapshot));
  } catch {
    // A read-only checkout only loses the cache, never the count.
  }
}

async function fetchCount(): Promise<number | null> {
  try {
    const token = process.env.GITHUB_TOKEN;
    const res = await fetch(REPO_API, {
      headers: {
        Accept: 'application/vnd.github+json',
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
      },
      signal: AbortSignal.timeout(3000),
    });
    if (!res.ok) return null;
    const { stargazers_count: count } = (await res.json()) as { stargazers_count?: unknown };
    return typeof count === 'number' && count > 0 ? count : null;
  } catch {
    return null;
  }
}

/** Resolves the layers above; options exist for the unit test. */
export async function resolveStars({
  now = Date.now(),
  cacheFile = defaultCacheFile(),
  fetchLive = fetchCount,
}: { now?: number; cacheFile?: string; fetchLive?: () => Promise<number | null> } = {}): Promise<number | null> {
  const cached = readCache(cacheFile);
  if (cached && now - Date.parse(cached.fetchedAt) < CACHE_TTL) return cached.count;
  const live = await fetchLive();
  if (live) {
    writeCache(cacheFile, { count: live, fetchedAt: new Date(now).toISOString() });
    return live;
  }
  if (cached) return cached.count;
  return isSnapshot(seed) ? seed.count : null;
}

let pending: Promise<number | null> | undefined;

export function githubStars(): Promise<number | null> {
  pending ??= resolveStars();
  return pending;
}

export { formatStars } from './github-stars-format.ts';
