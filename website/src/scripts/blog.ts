/** Blog helpers shared by the pages and the RSS feeds (no `astro:content` import). */
import { localePath, type Locale } from './locales.ts';

const SITE_ORIGIN = 'https://whispaste.de';
const WORDS_PER_MINUTE = 200;

export interface FeedPost {
  readonly slug: string;
  readonly title: string;
  readonly description: string;
  readonly date: Date;
}

/** Whole minutes to read `markdown`, never below 1. */
export function readingMinutes(markdown: string): number {
  const words = markdown.trim().split(/\s+/).filter(Boolean).length;
  return Math.max(1, Math.round(words / WORDS_PER_MINUTE));
}

export const feedPath = (lang: Locale): string => localePath(lang, 'blog/feed.xml').replace(/\/$/, '');

const xmlEscape = (value: string): string =>
  value.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

/** RSS 2.0 document for `posts` (newest first) in `lang`. */
export function buildFeed(lang: Locale, title: string, description: string, posts: readonly FeedPost[]): string {
  const items = posts
    .map((post) => {
      const url = new URL(localePath(lang, `blog/${post.slug}`), SITE_ORIGIN).href;
      return `    <item>
      <title>${xmlEscape(post.title)}</title>
      <link>${url}</link>
      <guid isPermaLink="true">${url}</guid>
      <pubDate>${post.date.toUTCString()}</pubDate>
      <description>${xmlEscape(post.description)}</description>
    </item>`;
    })
    .join('\n');
  const blogUrl = new URL(localePath(lang, 'blog'), SITE_ORIGIN).href;
  const self = new URL(feedPath(lang), SITE_ORIGIN).href;
  return `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">
  <channel>
    <title>${xmlEscape(title)}</title>
    <link>${blogUrl}</link>
    <description>${xmlEscape(description)}</description>
    <language>${lang}</language>
    <atom:link href="${self}" rel="self" type="application/rss+xml" />
${items}
  </channel>
</rss>
`;
}
