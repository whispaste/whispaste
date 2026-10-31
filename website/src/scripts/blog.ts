/** Blog helpers shared by the pages and the RSS feeds (no `astro:content` import). */
import { localePath, type Locale } from './locales.ts';

const WORDS_PER_MINUTE = 200;

/** Whole minutes to read `markdown`, never below 1. */
export function readingMinutes(markdown: string): number {
  const words = markdown.trim().split(/\s+/).filter(Boolean).length;
  return Math.max(1, Math.round(words / WORDS_PER_MINUTE));
}

export const feedPath = (lang: Locale): string => localePath(lang, 'blog/feed.xml').replace(/\/$/, '');
