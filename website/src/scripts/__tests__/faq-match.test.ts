import { describe, expect, it } from 'vitest';

import { DEFAULT_FAQ_KEYS } from '../../components/schema/builders.ts';
import { FAQ_INTENTS } from '../../data/faq-intents.ts';
import { CALIBRATION, TEST } from '../../data/faq-match-questions.ts';
import { buildFaqIndex } from '../faq-match/build.ts';
import { calibrate, evaluate, TARGET } from '../faq-match/calibrate.ts';
import { FAQ_MATCH_THRESHOLDS, MAX_CHOICES, match, type FaqIndex } from '../faq-match/engine.ts';
import { fold } from '../faq-match/normalize.ts';
import { i18n } from '../i18n.ts';
import { SUPPORTED_LOCALES, type Locale } from '../locales.ts';

/**
 * FAQ matcher of the contact widget (#351): calibration, held-out quality
 * and the decision contract the widget relies on.
 */

const indexes = new Map<Locale, FaqIndex>();
function indexFor(locale: Locale): FaqIndex {
  let index = indexes.get(locale);
  if (!index) {
    index = buildFaqIndex(locale);
    indexes.set(locale, index);
  }
  return index;
}

/** Shows the failing questions when a quality check goes red. */
function describeFailures(m: ReturnType<typeof evaluate>): string {
  return m.failures.map((f) => `${f.q.locale} "${f.q.q}" want ${f.q.expect}, got ${JSON.stringify(f.got)}`).join('\n');
}

describe('calibration', () => {
  it('the committed thresholds are what the calibration picks', () => {
    const result = calibrate(CALIBRATION, indexFor);
    expect(result, 'no threshold setting meets TARGET on the calibration set').not.toBeNull();
    // On a mismatch: copy result.thresholds into FAQ_MATCH_THRESHOLDS.
    expect(result?.thresholds).toEqual(FAQ_MATCH_THRESHOLDS);
  });

  it('calibration and test questions are separate', () => {
    const calibration = new Set(CALIBRATION.map((q) => `${q.locale}|${fold(q.q)}`));
    const overlap = TEST.filter((q) => calibration.has(`${q.locale}|${fold(q.q)}`));
    expect(overlap).toEqual([]);
  });
});

describe('held-out test questions', () => {
  const m = evaluate(TEST, indexFor, FAQ_MATCH_THRESHOLDS);

  it('direct answers are right (precision)', () => {
    expect(m.precision, describeFailures(m)).toBeGreaterThanOrEqual(TARGET.precision);
  });

  it('answerable questions reach a right entry (coverage)', () => {
    expect(m.coverage, describeFailures(m)).toBeGreaterThanOrEqual(0.9);
  });

  it('questions without an FAQ answer end at e-mail (fallback)', () => {
    expect(m.fallback, describeFailures(m)).toBeGreaterThanOrEqual(TARGET.fallback);
  });

  it('every site language is covered by both sets', () => {
    for (const locale of SUPPORTED_LOCALES) {
      expect(CALIBRATION.some((q) => q.locale === locale), locale).toBe(true);
      expect(TEST.some((q) => q.locale === locale), locale).toBe(true);
      expect(TEST.some((q) => q.locale === locale && q.expect === 'unknown'), locale).toBe(true);
    }
  });
});

describe('decision contract', () => {
  it('an empty or meaningless question falls back to e-mail', () => {
    for (const q of ['', '   ', '???', 'the and of']) {
      expect(match(indexFor('en'), q, FAQ_MATCH_THRESHOLDS)).toEqual({ kind: 'unknown' });
    }
  });

  it('a choice offers at most MAX_CHOICES entries, all real FAQ keys', () => {
    const t = { ...FAQ_MATCH_THRESHOLDS, minGap: 1, suggestScore: 0 };
    const got = match(indexFor('de'), 'Windows Mac Linux Preis offline', t);
    expect(got.kind).toBe('choose');
    if (got.kind !== 'choose') return;
    expect(got.keys.length).toBeLessThanOrEqual(MAX_CHOICES);
    for (const k of got.keys) expect(DEFAULT_FAQ_KEYS).toContain(k);
  });

  it('spelling without umlauts or accents matches the same entry', () => {
    const t = FAQ_MATCH_THRESHOLDS;
    // Compare with the expected entry, not with each other: two fallbacks would match too.
    expect(match(indexFor('de'), 'Was wird übertragen?', t)).toMatchObject({ kind: 'answer', key: 'privacy' });
    expect(match(indexFor('de'), 'Was wird ubertragen?', t)).toMatchObject({ kind: 'answer', key: 'privacy' });
    expect(match(indexFor('fr'), 'Ça marche hors ligne ?', t)).toMatchObject({ kind: 'answer', key: 'offline' });
    expect(match(indexFor('fr'), 'ca marche hors ligne', t)).toMatchObject({ kind: 'answer', key: 'offline' });
  });

  it('is deterministic and the index survives JSON (it is shipped as JSON)', () => {
    const index = indexFor('de');
    const shipped = JSON.parse(JSON.stringify(index)) as FaqIndex;
    for (const q of TEST.filter((x) => x.locale === 'de')) {
      expect(match(shipped, q.q, FAQ_MATCH_THRESHOLDS)).toEqual(match(index, q.q, FAQ_MATCH_THRESHOLDS));
    }
  });
});

describe('FAQ texts', () => {
  it('every FAQ entry has a question and an answer in every site language', () => {
    // build.ts falls back to '' for a missing text, so a gap would silently weaken the index.
    for (const locale of SUPPORTED_LOCALES) {
      for (const key of DEFAULT_FAQ_KEYS) {
        for (const part of ['q', 'a'] as const) {
          expect(i18n[locale][`faq.${key}.${part}`], `${locale} faq.${key}.${part}`).toBeTruthy();
        }
      }
    }
  });
});

describe('intent file', () => {
  it('has exactly one intent per FAQ entry, with variants in every language', () => {
    expect(FAQ_INTENTS.map((i) => i.key).sort()).toEqual([...DEFAULT_FAQ_KEYS].sort());
    for (const intent of FAQ_INTENTS) {
      for (const locale of SUPPORTED_LOCALES) {
        expect(intent.variants[locale].length, `${intent.key}/${locale}`).toBeGreaterThan(0);
      }
    }
  });

  it('labelled questions only name real FAQ entries', () => {
    for (const q of [...CALIBRATION, ...TEST]) {
      const keys = q.expect === 'choose' ? (q.keys ?? []) : q.expect === 'unknown' ? [] : [q.expect];
      if (q.expect === 'choose') expect(keys.length, q.q).toBeGreaterThan(1);
      for (const k of keys) expect(DEFAULT_FAQ_KEYS, q.q).toContain(k);
    }
  });
});
