import { describe, expect, it } from "vitest";
import { computeCorpusWer, computeRtf, computeWordErrorRate } from "../benchmark-engines-wer.mjs";

describe("computeWordErrorRate", () => {
  it("returns 0 for an exact match, ignoring case and punctuation", () => {
    const result = computeWordErrorRate(
      "And so, my fellow Americans.",
      "and so my fellow americans",
    );
    expect(result.wer).toBe(0);
    expect(result.substitutions).toBe(0);
    expect(result.deletions).toBe(0);
    expect(result.insertions).toBe(0);
    expect(result.refWordCount).toBe(5);
  });

  it("counts a single substitution", () => {
    const result = computeWordErrorRate("ask not what your country", "ask not what our country");
    expect(result.substitutions).toBe(1);
    expect(result.deletions).toBe(0);
    expect(result.insertions).toBe(0);
    expect(result.wer).toBeCloseTo(1 / 5);
  });

  it("counts a deletion (hypothesis missing a word)", () => {
    const result = computeWordErrorRate("ask not what your country", "ask what your country");
    expect(result.deletions).toBe(1);
    expect(result.wer).toBeCloseTo(1 / 5);
  });

  it("counts an insertion (hypothesis has an extra word)", () => {
    const result = computeWordErrorRate("ask not what", "ask really not what");
    expect(result.insertions).toBe(1);
    expect(result.wer).toBeCloseTo(1 / 3);
  });

  it("throws on an empty reference (WER is undefined without a denominator)", () => {
    expect(() => computeWordErrorRate("", "anything")).toThrow();
  });
});

describe("computeCorpusWer", () => {
  it("micro-averages across utterances (sums edits and ref words, not per-utterance WER)", () => {
    // Utterance A: 1 substitution in 5 ref words -> WER 0.2.
    // Utterance B: 1 deletion in 9 ref words -> WER 1/9.
    // A naive mean of the two WERs would be (0.2 + 1/9) / 2 ≈ 0.1556. The
    // corpus (micro-average) WER instead sums edits/ref-words across
    // utterances first: 2 edits / 14 ref words ≈ 0.1429 — the two disagree,
    // which is exactly what this test pins down.
    const result = computeCorpusWer([
      { reference: "ask not what your country", hypothesis: "ask not what our country" },
      {
        reference: "the quick brown fox jumps over the lazy dog",
        hypothesis: "the quick brown fox jumps over lazy dog",
      },
    ]);
    expect(result.wer).toBeCloseTo(2 / 14);
    expect(result.totalRefWords).toBe(14);
    expect(result.totalEdits).toBe(2);
    expect(result.sampleSize).toBe(2);
  });

  it("throws on an empty utterance list", () => {
    expect(() => computeCorpusWer([])).toThrow();
  });
});

describe("computeRtf", () => {
  it("divides processing time by audio duration", () => {
    expect(computeRtf(220, 11_000)).toBeCloseTo(0.02);
  });

  it("throws on non-positive audio duration", () => {
    expect(() => computeRtf(100, 0)).toThrow();
  });
});
