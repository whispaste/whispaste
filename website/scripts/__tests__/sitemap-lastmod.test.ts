/**
 * Sitemap `lastmod` only from real change dates (#1769): blog posts from
 * their frontmatter, changelog from the newest release, nothing else.
 */
import { fileURLToPath } from 'node:url';
import { describe, it, expect } from 'vitest';
import { collectLastmods, frontmatterDate, readBlogPosts } from '../sitemap-lastmod.mjs';

const SITE = 'https://whispaste.de';

describe('frontmatterDate', () => {
  it('prefers updated over date', () => {
    expect(frontmatterDate('---\ntitle: "x"\ndate: 2026-10-17\nupdated: 2026-11-02\n---\nbody')).toBe('2026-11-02');
  });

  it('falls back to date and ignores dates outside the frontmatter', () => {
    expect(frontmatterDate('---\ndate: 2026-10-17\n---\nupdated: 2027-01-01\n')).toBe('2026-10-17');
  });

  it('returns undefined without frontmatter or date', () => {
    expect(frontmatterDate('date: 2026-10-17')).toBeUndefined();
    expect(frontmatterDate('---\ntitle: "x"\n---\n')).toBeUndefined();
  });
});

describe('collectLastmods', () => {
  const map = collectLastmods({
    site: `${SITE}/`,
    posts: [
      { lang: 'de', slug: 'alt', date: '2026-10-17' },
      { lang: 'de', slug: 'neu', date: '2026-11-16' },
      { lang: 'en', slug: 'neu', date: '2026-11-16' },
    ],
    latestRelease: '2026-10-15T21:43:37Z',
    locales: ['de', 'en', 'fr'],
  });

  it('dates blog posts and indexes by their newest post', () => {
    expect(map.get(`${SITE}/blog/alt/`)).toBe('2026-10-17');
    expect(map.get(`${SITE}/en/blog/neu/`)).toBe('2026-11-16');
    expect(map.get(`${SITE}/blog/`)).toBe('2026-11-16');
    expect(map.get(`${SITE}/en/blog/`)).toBe('2026-11-16');
  });

  it('dates every changelog page by the newest release', () => {
    for (const url of [`${SITE}/changelog/`, `${SITE}/en/changelog/`, `${SITE}/fr/changelog/`]) {
      expect(map.get(url)).toBe('2026-10-15T21:43:37Z');
    }
  });

  it('leaves every other page without lastmod', () => {
    expect(map.has(`${SITE}/`)).toBe(false);
    expect(map.has(`${SITE}/download/`)).toBe(false);
    expect(map.size).toBe(3 + 2 + 3);
  });
});

describe('readBlogPosts', () => {
  it('finds a dated post in every blog language', () => {
    const posts = readBlogPosts(fileURLToPath(new URL('../../src/content/blog/', import.meta.url)));
    const langs = new Set(posts.map((post) => post.lang));
    expect(langs).toEqual(new Set(['de', 'en']));
    expect(posts.every((post) => /^\d{4}-\d{2}-\d{2}/.test(post.date))).toBe(true);
  });
});
