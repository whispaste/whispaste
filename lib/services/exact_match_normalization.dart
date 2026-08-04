/// Shared exact-match normalization for trigger-phrase comparisons.
///
/// Used by the Snippet-Picker (`snippet_picker_dispatch.dart`) to compare a
/// transcript against its configured trigger word.
library;

/// Normalizes [input] for exact-match comparison: lowercases, then folds
/// every run of non-letter/non-digit characters — punctuation anywhere in
/// the phrase (not just trailing), whitespace, and word-separating
/// characters like "-" — into a single space.
///
/// Folding hyphens into the same bucket as whitespace deliberately makes
/// "test-script" and "test script" the same trigger: dictation engines are
/// inconsistent about which one they emit for a given spoken phrase (as are
/// speakers about a trailing period, a stray comma, or exact spacing), and a
/// trigger shouldn't silently miss over a difference the user has no direct
/// control over. Applied to both the finished transcript and every trigger
/// phrase before comparing them — only the *comparison* is normalized, the
/// transcript that eventually reaches history/paste is never touched by
/// this.
String normalizeForExactMatch(String input) {
  final lowered = input.toLowerCase();
  final wordsOnly = lowered.replaceAll(
    RegExp(r'[^\p{L}\p{N}]+', unicode: true),
    ' ',
  );
  return wordsOnly.trim();
}
