import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import seed from '../../data/github-stars.json';
import { formatStars, resolveStars } from '../github-stars.ts';

const NOW = Date.parse('2026-10-16T12:00:00Z');
const HOUR = 60 * 60 * 1000;

function cacheWith(count: number, ageMs: number): string {
  const file = join(mkdtempSync(join(tmpdir(), 'stars-')), 'cache.json');
  writeFileSync(file, JSON.stringify({ count, fetchedAt: new Date(NOW - ageMs).toISOString() }));
  return file;
}

const emptyCache = () => join(mkdtempSync(join(tmpdir(), 'stars-')), 'cache.json');
const failing = async () => null;
const unexpected = async (): Promise<number | null> => {
  throw new Error('fresh cache must not hit the API');
};

describe('github star count', () => {
  it('a fresh cache answers without a request', async () => {
    expect(await resolveStars({ now: NOW, cacheFile: cacheWith(70, HOUR), fetchLive: unexpected })).toBe(70);
  });

  it('a stale cache is refreshed from the API', async () => {
    const file = cacheWith(70, 7 * HOUR);
    expect(await resolveStars({ now: NOW, cacheFile: file, fetchLive: async () => 81 })).toBe(81);
    expect(JSON.parse(readFileSync(file, 'utf8')).count).toBe(81);
  });

  it('a failed request keeps the last cached value, however old', async () => {
    expect(await resolveStars({ now: NOW, cacheFile: cacheWith(70, 90 * 24 * HOUR), fetchLive: failing })).toBe(70);
  });

  it('without cache and API the committed last-known value is the floor', async () => {
    expect(seed.count).toBeGreaterThan(0);
    expect(await resolveStars({ now: NOW, cacheFile: emptyCache(), fetchLive: failing })).toBe(seed.count);
  });

  it('formats compactly per locale', () => {
    expect(formatStars(59, 'de')).toBe('59');
    expect(formatStars(1234, 'en')).toBe('1.2K');
  });
});
