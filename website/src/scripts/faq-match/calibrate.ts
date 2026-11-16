/**
 * Evaluation and calibration of the FAQ matcher (#351).
 *
 * Each labelled question says what the widget should do:
 *   - `expect: '<key>'`   one FAQ entry answers it;
 *   - `expect: 'choose'`  ambiguous, `keys` lists the entries that fit;
 *   - `expect: 'unknown'` no FAQ answer, the e-mail fallback is right.
 *
 * Metrics:
 *   - precision: of all direct answers, the share that is right;
 *   - coverage: of all answerable questions, the share that reaches a right
 *     entry, directly or inside the choice;
 *   - direct: of all clear questions, the share answered right at once;
 *   - fallback: of all unknown questions, the share that ends at e-mail.
 */

import type { Locale } from '../locales.ts';
import { decide, rank, type FaqIndex, type MatchResult, type MatchThresholds } from './engine.ts';

export interface LabelledQuestion {
  readonly locale: Locale;
  readonly q: string;
  readonly expect: string;
  /** Entries that fit an ambiguous question (`expect: 'choose'`). */
  readonly keys?: readonly string[];
}

export interface Metrics {
  readonly precision: number;
  readonly coverage: number;
  readonly direct: number;
  readonly fallback: number;
  readonly failures: readonly { q: LabelledQuestion; got: MatchResult }[];
}

type Ranked = readonly { key: string; score: number }[];

function accepted(q: LabelledQuestion): readonly string[] {
  return q.expect === 'choose' ? (q.keys ?? []) : [q.expect];
}

function score(rows: readonly { q: LabelledQuestion; ranked: Ranked }[], t: MatchThresholds): Metrics {
  let answered = 0;
  let answeredRight = 0;
  let answerable = 0;
  let covered = 0;
  let clear = 0;
  let directRight = 0;
  let unknown = 0;
  let fellBack = 0;
  const failures: { q: LabelledQuestion; got: MatchResult }[] = [];

  for (const { q, ranked } of rows) {
    const got = decide(ranked, t);
    const ok = accepted(q);
    const rightAnswer = got.kind === 'answer' && ok.includes(got.key);
    if (got.kind === 'answer') {
      answered++;
      if (rightAnswer) answeredRight++;
    }
    if (q.expect === 'unknown') {
      unknown++;
      if (got.kind === 'unknown') fellBack++;
      else failures.push({ q, got });
      continue;
    }
    answerable++;
    if (q.expect !== 'choose') {
      clear++;
      if (rightAnswer) directRight++;
    }
    if (rightAnswer || (got.kind === 'choose' && got.keys.some((k) => ok.includes(k)))) covered++;
    else failures.push({ q, got });
  }
  const share = (a: number, b: number) => (b === 0 ? 1 : a / b);
  return {
    precision: share(answeredRight, answered),
    coverage: share(covered, answerable),
    direct: share(directRight, clear),
    fallback: share(fellBack, unknown),
    failures,
  };
}

function rankAll(questions: readonly LabelledQuestion[], indexFor: (locale: Locale) => FaqIndex) {
  return questions.map((q) => ({ q, ranked: rank(indexFor(q.locale), q.q) }));
}

export function evaluate(
  questions: readonly LabelledQuestion[],
  indexFor: (locale: Locale) => FaqIndex,
  t: MatchThresholds,
): Metrics {
  return score(rankAll(questions, indexFor), t);
}

/** Required quality; calibration only picks thresholds that meet it. */
export const TARGET = { precision: 0.95, fallback: 0.9 } as const;

function steps(from: number, to: number, step: number): number[] {
  const out: number[] = [];
  for (let i = 0; from + i * step <= to + 1e-9; i++) out.push(Math.round((from + i * step) * 100) / 100);
  return out;
}

/**
 * Grid search over the thresholds: among all settings that meet [TARGET],
 * the one with the best coverage, then the most direct answers, then the
 * largest lead (the safest against a wrong direct answer); on a full tie the
 * first one found, which is the lowest score. Deterministic.
 */
export function calibrate(
  questions: readonly LabelledQuestion[],
  indexFor: (locale: Locale) => FaqIndex,
): { thresholds: MatchThresholds; metrics: Metrics } | null {
  const rows = rankAll(questions, indexFor);
  let best: { thresholds: MatchThresholds; metrics: Metrics } | null = null;
  for (const suggestScore of steps(0.05, 0.4, 0.01)) {
    for (const minScore of steps(suggestScore, 0.6, 0.01)) {
      for (const minGap of steps(0, 0.3, 0.01)) {
        const thresholds = { minScore, minGap, suggestScore };
        const metrics = score(rows, thresholds);
        if (metrics.precision < TARGET.precision || metrics.fallback < TARGET.fallback) continue;
        const prev = best?.metrics;
        if (
          !best ||
          !prev ||
          metrics.coverage > prev.coverage ||
          (metrics.coverage === prev.coverage && metrics.direct > prev.direct) ||
          (metrics.coverage === prev.coverage &&
            metrics.direct === prev.direct &&
            minGap > best.thresholds.minGap)
        ) {
          best = { thresholds, metrics };
        }
      }
    }
  }
  return best;
}
