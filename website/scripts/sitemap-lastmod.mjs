/**
 * Real `lastmod` dates for the sitemap (#1769).
 *
 * A build timestamp on every URL tells crawlers nothing, so Google ignores it.
 * Only pages with a reliable change date get a `lastmod`:
 *   - blog posts: their frontmatter `updated`, else `date`
 *   - blog indexes: the newest post of that language
 *   - changelog pages: the newest release in `src/data/releases.json`,
 *     the snapshot their static HTML is built from
 * Every other page goes without `lastmod` rather than with a wrong one.
 */
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

/** Path prefix per language; German is the default locale without prefix. */
const prefix = (lang) => (lang === 'de' ? '' : `/${lang}`);

/**
 * Reads `updated` (preferred) or `date` from a markdown frontmatter block.
 * @param {string} markdown
 * @returns {string | undefined} the date as written, e.g. `2026-11-16`
 */
export function frontmatterDate(markdown) {
  const block = /^---\r?\n([\s\S]*?)\r?\n---/.exec(markdown)?.[1];
  if (!block) return undefined;
  const field = (name) =>
    new RegExp(`^${name}:\\s*["']?(\\d{4}-\\d{2}-\\d{2}[^"'\\s]*)["']?\\s*$`, 'm').exec(block)?.[1];
  return field('updated') ?? field('date');
}

/**
 * Maps absolute page URLs to their `lastmod`.
 * @param {{
 *   site: string,
 *   posts: { lang: string, slug: string, date: string }[],
 *   latestRelease?: string,
 *   locales: string[],
 * }} input
 * @returns {Map<string, string>}
 */
export function collectLastmods({ site, posts, latestRelease, locales }) {
  const base = site.replace(/\/$/, '');
  const map = new Map();
  for (const { lang, slug, date } of posts) {
    map.set(`${base}${prefix(lang)}/blog/${slug}/`, date);
    const index = `${base}${prefix(lang)}/blog/`;
    if (!map.has(index) || map.get(index) < date) map.set(index, date);
  }
  if (latestRelease) {
    for (const lang of locales) map.set(`${base}${prefix(lang)}/changelog/`, latestRelease);
  }
  return map;
}

/**
 * Reads all blog posts below `blogDir/<lang>/<slug>.md` that carry a date.
 * @param {string} blogDir
 * @returns {{ lang: string, slug: string, date: string }[]}
 */
export function readBlogPosts(blogDir) {
  return readdirSync(blogDir, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .flatMap(({ name: lang }) =>
      readdirSync(join(blogDir, lang))
        .filter((file) => file.endsWith('.md'))
        .flatMap((file) => {
          const date = frontmatterDate(readFileSync(join(blogDir, lang, file), 'utf8'));
          return date ? [{ lang, slug: file.slice(0, -'.md'.length), date }] : [];
        }),
    );
}

/**
 * Newest `publishedAt` in the releases snapshot, if any.
 * @param {string} releasesFile
 * @returns {string | undefined}
 */
export function readLatestRelease(releasesFile) {
  const { releases = [] } = JSON.parse(readFileSync(releasesFile, 'utf8'));
  return releases
    .map((release) => release.publishedAt)
    .filter(Boolean)
    .sort()
    .at(-1);
}
