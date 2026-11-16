/**
 * FAQ matcher (#351): ranks the FAQ entries of one locale against a free
 * question with BM25 and decides between a direct answer, a short choice
 * and the e-mail fallback.
 *
 * The index is plain JSON, built at build time (`build.ts`) and shipped per
 * page, so the browser does no indexing and loads no third-party code.
 * Deterministic: the same index and question always give the same result.
 */

import { addFeatures, familyWeight, features, type Feature } from './normalize.ts';

/** One FAQ entry before indexing: weighted text fields. */
export interface FaqSourceDoc {
  /** FAQ key (`free`, `offline`, …); the answer lives at `#faq-<key>`. */
  readonly key: string;
  readonly fields: readonly (readonly [text: string, weight: number])[];
}

export interface FaqIndexDoc {
  readonly key: string;
  /** Feature → weighted term frequency. */
  readonly tf: Readonly<Record<Feature, number>>;
  readonly len: number;
}

export interface FaqIndex {
  readonly docs: readonly FaqIndexDoc[];
  /** Feature → inverse document frequency (BM25 form, always > 0). */
  readonly idf: Readonly<Record<Feature, number>>;
  readonly avgLen: number;
}

export interface MatchThresholds {
  /** Normalised score the best entry needs for a direct answer. */
  readonly minScore: number;
  /**
   * Lead over the second-best entry needed for a direct answer, relative to
   * the best score: (best - second) / best.
   */
  readonly minGap: number;
  /** Normalised score an entry needs to be offered in the choice. */
  readonly suggestScore: number;
}

export type MatchResult =
  | { readonly kind: 'answer'; readonly key: string; readonly score: number }
  | { readonly kind: 'choose'; readonly keys: readonly string[] }
  | { readonly kind: 'unknown' };

/** Most entries a choice offers. */
export const MAX_CHOICES = 3;

/** Longer input is cut before matching; a real question is far shorter. */
export const MAX_QUESTION_LENGTH = 500;

/**
 * Thresholds picked by `calibrate()` on the calibration questions
 * (`src/data/faq-match-questions.ts`). Do not edit by hand: after changing
 * intents, FAQ texts or the matcher, run the calibration test and copy the
 * values it reports (internal-notes).
 */
export const FAQ_MATCH_THRESHOLDS: MatchThresholds = {
  minScore: 0.21,
  minGap: 0.13,
  suggestScore: 0.21,
};

const K1 = 1.2;
const B = 0.75;

export function buildIndex(sources: readonly FaqSourceDoc[]): FaqIndex {
  const docs: FaqIndexDoc[] = sources.map((src) => {
    const bag = new Map<Feature, number>();
    for (const [text, weight] of src.fields) addFeatures(bag, text, weight);
    let len = 0;
    for (const v of bag.values()) len += v;
    return { key: src.key, tf: Object.fromEntries(bag), len };
  });
  const df = new Map<Feature, number>();
  for (const doc of docs) {
    for (const f of Object.keys(doc.tf)) df.set(f, (df.get(f) ?? 0) + 1);
  }
  const n = docs.length;
  const idf: Record<Feature, number> = {};
  for (const [f, d] of df) idf[f] = Math.log(1 + (n - d + 0.5) / (d + 0.5));
  const avgLen = docs.reduce((sum, d) => sum + d.len, 0) / Math.max(n, 1);
  return { docs, idf, avgLen };
}

/**
 * Every entry with its score normalised to 0..1: the BM25 score divided by
 * the score the question would reach if each of its features were saturated
 * in one entry. Sorted best first, ties by key for determinism.
 */
export function rank(index: FaqIndex, question: string): { key: string; score: number }[] {
  const query = features(question.slice(0, MAX_QUESTION_LENGTH));
  // A feature no entry contains still counts toward the ceiling (as if one
  // entry had it), so an off-topic question with one stray hit stays low.
  const n = index.docs.length;
  const unseenIdf = Math.log(1 + (n - 0.5) / 1.5);
  let upper = 0;
  for (const [f, qw] of query) {
    upper += qw * familyWeight(f) * (index.idf[f] ?? unseenIdf) * (K1 + 1);
  }
  const ranked = index.docs.map((doc) => {
    if (upper === 0) return { key: doc.key, score: 0 };
    let s = 0;
    const norm = K1 * (1 - B + (B * doc.len) / index.avgLen);
    for (const [f, qw] of query) {
      const tf = doc.tf[f];
      const idf = index.idf[f];
      if (tf === undefined || idf === undefined) continue;
      s += qw * familyWeight(f) * idf * ((tf * (K1 + 1)) / (tf + norm));
    }
    return { key: doc.key, score: s / upper };
  });
  return ranked.sort((a, b) => b.score - a.score || a.key.localeCompare(b.key));
}

export function match(index: FaqIndex, question: string, t: MatchThresholds): MatchResult {
  return decide(rank(index, question), t);
}

/** The decision on an already ranked list (best first). */
export function decide(
  ranked: readonly { key: string; score: number }[],
  t: MatchThresholds,
): MatchResult {
  const [best, second] = ranked;
  if (!best || best.score < t.suggestScore) return { kind: 'unknown' };
  const lead = (best.score - (second?.score ?? 0)) / best.score;
  if (best.score >= t.minScore && lead >= t.minGap) {
    return { kind: 'answer', key: best.key, score: best.score };
  }
  const keys = ranked
    .filter((r) => r.score >= t.suggestScore)
    .slice(0, MAX_CHOICES)
    .map((r) => r.key);
  return { kind: 'choose', keys };
}
