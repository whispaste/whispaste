/// Pure text-transform helpers applied to a finished transcript before it
/// is saved/pasted. Kept free-standing (not private methods on
/// [RecordingOrchestrator]) so they are directly unit-testable without any
/// pipeline/provider setup.
library;

/// Sentence-level punctuation marks WhisPaste's STT engines are known to
/// insert: terminal marks, clause separators, and the em/en dash + ellipsis
/// some engines use as a clause connector.
///
/// Deliberately excludes:
/// - the apostrophe (`'`/`'`) — word-internal (e.g. "don't", "Silvio's"),
///   changes word meaning rather than sentence structure;
/// - the hyphen (`-`) — word-internal (e.g. compound words), same reason;
/// - digits and letters — never touched.
final _sentencePunctuation = RegExp(r'[.,!?;:…—–]');

/// Deterministically removes [_sentencePunctuation] from [text] and
/// collapses the whitespace left behind, so `"Hello, world."` becomes
/// `"Hello world"` rather than `"Hello  world"`.
///
/// Engine-independent by construction — this is plain string processing on
/// the already-transcribed text, applied uniformly regardless of which STT
/// engine or provider produced it. See [SttSettings.stripPunctuation].
String stripPunctuation(String text) {
  return text
      .replaceAll(_sentencePunctuation, '')
      .replaceAll(RegExp(r' {2,}'), ' ')
      .trim();
}
