/// Pure helper for truncating an `initial_prompt` string to a real
/// whisper.cpp token budget.
///
/// Fixes a silent-data-loss bug: whisper.cpp truncates the *tokenized*
/// `initial_prompt` to a small internal ceiling (`n_max_text_ctx` capped by
/// half the context window — ~63 tokens for WhisPaste's configuration)
/// independently of any char-length limit the app validates against. Any
/// prompt roughly 250–1024 characters long passed pre-flight validation
/// cleanly while silently losing content inside the native engine, with no
/// signal anywhere in the app. See [PromptTokenCounter]'s doc comment for
/// the full mechanism.
library;

/// Truncates [text] to the largest whitespace-word-aligned PREFIX whose
/// token count (via [countTokens]) is at most [budgetTokens].
///
/// Front-anchored on purpose — keeps the START of [text] and drops the
/// tail — the deliberate opposite of whisper.cpp's own internal
/// `initial_prompt` handling, which silently keeps only the LAST ~63
/// tokens. Front-anchoring only pays off if the caller puts what matters
/// most at the front: [SttServerStateNotifier._resolveEffectivePrompt]
/// puts the user's custom vocabulary before the older rolling context
/// specifically so vocabulary survives this truncation first.
///
/// Binary search over word count rather than character count: whisper's
/// BPE tokenizer has no fixed chars-per-token ratio, and [countTokens] only
/// reports a whole-string count (no token→text-offset mapping), so
/// bisecting the word boundary is the simplest approach that stays correct
/// without decoding tokens back to text. Costs at most `log2(wordCount)`
/// calls to [countTokens], and only runs at all when the combined prompt
/// actually risks exceeding the budget (rare — most prompts are short).
///
/// Returns `text` unchanged if it already fits. Returns `''` if not even a
/// single leading word fits [budgetTokens].
Future<String> truncatePromptToTokenBudget(
  String text,
  int budgetTokens,
  Future<int> Function(String text) countTokens,
) async {
  if (text.isEmpty || budgetTokens <= 0) return '';
  if (await countTokens(text) <= budgetTokens) return text;

  final words = text.split(RegExp(r'\s+'))..removeWhere((w) => w.isEmpty);
  if (words.isEmpty) return '';

  // Classic "find the largest prefix length that still satisfies the
  // predicate" binary search: `lo` always holds a known-fitting prefix
  // length (0 trivially fits since budgetTokens > 0 is already checked
  // above), `hi` starts at the full word count, which is already known
  // NOT to fit (checked above).
  var lo = 0;
  var hi = words.length;
  while (lo < hi) {
    final mid = lo + ((hi - lo + 1) ~/ 2);
    if (mid == 0) break;
    final candidate = words.sublist(0, mid).join(' ');
    if (await countTokens(candidate) <= budgetTokens) {
      lo = mid;
    } else {
      hi = mid - 1;
    }
  }
  return words.sublist(0, lo).join(' ');
}
