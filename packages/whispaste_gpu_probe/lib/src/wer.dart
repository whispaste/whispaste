/// Word Error Rate (WER) computation for transcript quality measurement.
///
/// WER = (substitutions + insertions + deletions) / number_of_reference_words
///
/// computed via word-level Levenshtein edit distance on the normalized token
/// lists.
///
/// ## Normalization
/// Both strings are normalized before comparison:
/// - Lowercased
/// - Punctuation removed
/// - Whitespace collapsed and trimmed
///
/// ## Edge cases
/// - Empty reference + empty hypothesis → 0.0 (both normalized to empty)
/// - Empty reference + non-empty hypothesis → 0.0 (no reference words to penalize)
/// - Empty hypothesis + non-empty reference → 1.0 (all reference words deleted)
library;

import 'dart:math' as math;

/// Normalizes [text] for WER computation:
/// - Converts to lowercase
/// - Removes all punctuation characters
/// - Collapses runs of whitespace and trims edges
String normalizeForWer(String text) {
  // Remove punctuation (any character that is not a letter, digit, or whitespace).
  final withoutPunctuation = text.replaceAll(
    RegExp(r'[^\p{L}\p{N}\s]', unicode: true),
    '',
  );
  // Lowercase and collapse whitespace.
  return withoutPunctuation.toLowerCase().trim().replaceAll(
    RegExp(r'\s+'),
    ' ',
  );
}

/// Computes Word Error Rate of [hypothesis] against [reference].
///
/// Both inputs are normalized before comparison (see [normalizeForWer]).
///
/// Returns a value in [0.0, ∞) — typically [0.0, 1.0] but can exceed 1.0
/// when there are more insertions than reference words. Returns exactly 0.0
/// when the reference is empty (nothing to be wrong about).
double computeWer(String hypothesis, String reference) {
  final hypTokens = _tokenize(normalizeForWer(hypothesis));
  final refTokens = _tokenize(normalizeForWer(reference));

  if (refTokens.isEmpty) return 0.0;

  final editDistance = _wordLevenshtein(hypTokens, refTokens);
  return editDistance / refTokens.length;
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// Splits a normalized string into word tokens.
/// Returns an empty list for an empty string.
List<String> _tokenize(String normalized) {
  if (normalized.isEmpty) return const [];
  return normalized.split(' ');
}

/// Computes word-level Levenshtein edit distance between [hyp] and [ref].
///
/// Each operation (substitution, insertion, deletion) has cost 1.
int _wordLevenshtein(List<String> hyp, List<String> ref) {
  final m = hyp.length;
  final n = ref.length;

  // dp[i][j] = edit distance between hyp[0..i) and ref[0..j).
  final dp = List.generate(m + 1, (i) => List.filled(n + 1, 0));

  for (var i = 0; i <= m; i++) {
    dp[i][0] = i; // all deletions
  }
  for (var j = 0; j <= n; j++) {
    dp[0][j] = j; // all insertions
  }

  for (var i = 1; i <= m; i++) {
    for (var j = 1; j <= n; j++) {
      if (hyp[i - 1] == ref[j - 1]) {
        dp[i][j] = dp[i - 1][j - 1];
      } else {
        dp[i][j] =
            1 +
            math.min(
              dp[i - 1][j - 1], // substitution
              math.min(
                dp[i - 1][j], // deletion (drop hyp word)
                dp[i][j - 1], // insertion (skip ref word)
              ),
            );
      }
    }
  }

  return dp[m][n];
}
