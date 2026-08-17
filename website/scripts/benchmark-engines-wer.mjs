/**
 * Word Error Rate (WER) + Real-Time Factor (RTF) — the two metrics the
 * engine-benchmark page (`/engine-benchmarks/`) reports per hardware class.
 *
 * WER uses the standard word-level Levenshtein alignment (substitutions +
 * deletions + insertions, divided by the reference word count) — the same
 * definition used by every published whisper.cpp/ASR benchmark, so numbers
 * here are comparable to third-party sources.
 *
 * RTF follows the project's own definition (see `lib/services/stt/
 * stt_benchmark.dart`): processing_time_ms / audio_duration_ms. Lower is
 * faster; 1.0 means "exactly real-time".
 */

function tokenize(text) {
  return text
    .toLowerCase()
    .replace(/[.,!?;:"'()]/g, "")
    .trim()
    .split(/\s+/)
    .filter(Boolean);
}

/**
 * @param {string} reference ground-truth transcript
 * @param {string} hypothesis engine output
 */
export function computeWordErrorRate(reference, hypothesis) {
  const ref = tokenize(reference);
  const hyp = tokenize(hypothesis);
  if (ref.length === 0) {
    throw new Error("computeWordErrorRate: reference must not be empty");
  }

  // Standard DP alignment: dp[i][j] = edit distance between ref[0..i) and hyp[0..j).
  const dp = Array.from({ length: ref.length + 1 }, () => new Array(hyp.length + 1).fill(0));
  for (let i = 0; i <= ref.length; i++) dp[i][0] = i;
  for (let j = 0; j <= hyp.length; j++) dp[0][j] = j;
  for (let i = 1; i <= ref.length; i++) {
    for (let j = 1; j <= hyp.length; j++) {
      if (ref[i - 1] === hyp[j - 1]) {
        dp[i][j] = dp[i - 1][j - 1];
      } else {
        dp[i][j] = 1 + Math.min(dp[i - 1][j], dp[i][j - 1], dp[i - 1][j - 1]);
      }
    }
  }

  // Backtrack to split the total edit distance into sub/del/ins counts.
  let i = ref.length;
  let j = hyp.length;
  let substitutions = 0;
  let deletions = 0;
  let insertions = 0;
  while (i > 0 || j > 0) {
    if (i > 0 && j > 0 && ref[i - 1] === hyp[j - 1]) {
      i--;
      j--;
      continue;
    }
    const sub = i > 0 && j > 0 ? dp[i - 1][j - 1] : Infinity;
    const del = i > 0 ? dp[i - 1][j] : Infinity;
    const ins = j > 0 ? dp[i][j - 1] : Infinity;
    const best = Math.min(sub, del, ins);
    if (best === sub) {
      substitutions++;
      i--;
      j--;
    } else if (best === del) {
      deletions++;
      i--;
    } else {
      insertions++;
      j--;
    }
  }

  return {
    wer: (substitutions + deletions + insertions) / ref.length,
    substitutions,
    deletions,
    insertions,
    refWordCount: ref.length,
  };
}

/**
 * Corpus-level (micro-averaged) WER across multiple utterances: sums edits
 * and reference word counts first, then divides — NOT the mean of
 * per-utterance WER values, which over-weights short utterances.
 *
 * @param {{ reference: string, hypothesis: string }[]} pairs
 */
export function computeCorpusWer(pairs) {
  if (pairs.length === 0) {
    throw new Error("computeCorpusWer: pairs must not be empty");
  }
  let totalEdits = 0;
  let totalRefWords = 0;
  for (const { reference, hypothesis } of pairs) {
    const { substitutions, deletions, insertions, refWordCount } = computeWordErrorRate(
      reference,
      hypothesis,
    );
    totalEdits += substitutions + deletions + insertions;
    totalRefWords += refWordCount;
  }
  return {
    wer: totalEdits / totalRefWords,
    totalEdits,
    totalRefWords,
    sampleSize: pairs.length,
  };
}

/**
 * @param {number} processingMs wall-clock time to transcribe (excludes one-time model load)
 * @param {number} audioDurationMs duration of the input audio
 */
export function computeRtf(processingMs, audioDurationMs) {
  if (!(audioDurationMs > 0)) {
    throw new Error("computeRtf: audioDurationMs must be positive");
  }
  return processingMs / audioDurationMs;
}
