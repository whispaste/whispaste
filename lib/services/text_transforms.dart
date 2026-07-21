/// Pure text-transform helpers applied to a finished transcript before it
/// is saved/pasted. Kept free-standing (not private methods on
/// [RecordingOrchestrator]) so they are directly unit-testable without any
/// pipeline/provider setup.
library;

/// Punctuation marks that are always sentence-level — never legitimately
/// part of a number: terminal marks, clause separators, and the em/en dash
/// + ellipsis some STT engines use as a clause connector.
///
/// Deliberately excludes:
/// - the apostrophe (`'`/`'`) — word-internal (e.g. "don't", "Silvio's"),
///   changes word meaning rather than sentence structure;
/// - the hyphen (`-`) — word-internal (e.g. compound words), same reason;
/// - the period/comma — see [_ambiguousPunctuation] below;
/// - digits and letters — never touched.
final _alwaysStrip = RegExp(r'[!?;:…—–]');

/// The period and comma are ambiguous: both are legitimate inside a number
/// (decimal point OR thousands separator — either can be `.` or `,`
/// depending on locale, e.g. "3.14" vs "3,14", "1,000" vs "1.000") as well
/// as ordinary sentence punctuation ("Hello.", "Wait, actually"). Stripping
/// them unconditionally would corrupt numbers, not just formatting — "2.5
/// kilograms" becoming "25 kilograms" changes the actual value, which is
/// worse than leaving punctuation in.
///
/// Resolution: only strip a period/comma when it is NOT flanked by a digit
/// on both sides. This keeps decimal points, thousands separators, version
/// numbers ("1.2.53"), and prices ("$19.99") fully intact, while a
/// sentence-ending period after a number ("The answer is 42.") is still
/// removed.
final _ambiguousPunctuation = RegExp(r'[.,](?!\d)|(?<!\d)[.,]');

/// Deterministically removes [_alwaysStrip] and [_ambiguousPunctuation]
/// matches from [text] and collapses the whitespace left behind, so
/// `"Hello, world."` becomes `"Hello world"` rather than `"Hello  world"`.
///
/// Engine-independent by construction — this is plain string processing on
/// the already-transcribed text, applied uniformly regardless of which STT
/// engine or provider produced it. See [SttSettings.stripPunctuation].
String stripPunctuation(String text) {
  return text
      .replaceAll(_alwaysStrip, '')
      .replaceAll(_ambiguousPunctuation, '')
      .replaceAll(RegExp(r' {2,}'), ' ')
      .trim();
}
