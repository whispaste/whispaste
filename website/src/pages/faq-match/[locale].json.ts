/**
 * FAQ matcher data per site language (#352): the build-time index plus the
 * FAQ question and answer texts, served as `/faq-match/<locale>.json`. The
 * contact widget loads it only when a visitor asks a question, so pages do
 * not carry ~100 KB of index each.
 */
import type { APIRoute, GetStaticPaths } from 'astro';
import { DEFAULT_FAQ_KEYS } from '../../components/schema/builders.ts';
import { buildFaqIndex } from '../../scripts/faq-match/build.ts';
import { i18n } from '../../scripts/i18n.ts';
import { SUPPORTED_LOCALES, type Locale } from '../../scripts/locales.ts';
import type { FaqMatchData } from '../../scripts/faq-match/data.ts';

export const getStaticPaths: GetStaticPaths = () => SUPPORTED_LOCALES.map((locale) => ({ params: { locale } }));

export const GET: APIRoute = ({ params }) => {
  const locale = params.locale as Locale;
  const dict = i18n[locale];
  const data: FaqMatchData = {
    index: buildFaqIndex(locale),
    faq: Object.fromEntries(DEFAULT_FAQ_KEYS.map((key) => [key, { q: dict[`faq.${key}.q`] ?? '', a: dict[`faq.${key}.a`] ?? '' }])),
  };
  return new Response(JSON.stringify(data), { headers: { 'Content-Type': 'application/json; charset=utf-8' } });
};
