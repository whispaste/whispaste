import { describe, expect, it } from "vitest";
import { computeRtf, computeWordErrorRate } from "../benchmark-engines-wer.mjs";

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

describe("computeRtf", () => {
  it("divides processing time by audio duration", () => {
    expect(computeRtf(220, 11_000)).toBeCloseTo(0.02);
  });

  it("throws on non-positive audio duration", () => {
    expect(() => computeRtf(100, 0)).toThrow();
  });
});
