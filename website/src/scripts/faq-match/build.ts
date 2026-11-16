/**
 * Build-time index of the FAQ matcher (#351): one index per site language
 * from the FAQ texts (`faq.<key>.q/a`) and the intent file. Imports every
 * dictionary, so only the build (Astro frontmatter, tests) uses this file;
 * the page receives the finished JSON.
 */

import { FAQ_INTENTS } from '../../data/faq-intents.ts';
import { DEFAULT_FAQ_KEYS } from '../../components/schema/builders.ts';
import { i18n } from '../i18n.ts';
import type { Locale } from '../locales.ts';
import { buildIndex, type FaqIndex, type FaqSourceDoc } from './engine.ts';

/** Field weights: the question line counts most, the answer body least. */
const WEIGHT = { question: 3, variant: 2, answer: 0.5 } as const;

export function faqSources(locale: Locale): FaqSourceDoc[] {
  const dict = i18n[locale];
  return DEFAULT_FAQ_KEYS.map((key) => {
    const intent = FAQ_INTENTS.find((i) => i.key === key);
    const fields: [string, number][] = [
      [dict[`faq.${key}.q`] ?? '', WEIGHT.question],
      [dict[`faq.${key}.a`] ?? '', WEIGHT.answer],
    ];
    for (const v of intent?.variants[locale] ?? []) fields.push([v, WEIGHT.variant]);
    return { key, fields };
  });
}

export function buildFaqIndex(locale: Locale): FaqIndex {
  return buildIndex(faqSources(locale));
}
