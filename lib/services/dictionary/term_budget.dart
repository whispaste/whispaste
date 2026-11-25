/// How much of the term list each recognition can take (#622, #1969).
///
/// The term list (`stt.customVocabulary`) is written most used first
/// (`auto_terms.dart`), so every cut here keeps the FRONT and drops whole
/// terms from the end: the most valuable terms survive, and no term reaches
/// an engine half cut (a cut "Mac Studio" would bias towards "Mac").
///
/// Per recognition:
/// - On-device Whisper: one `initial_prompt` of
///   `SttServerStateNotifier.promptTokenBudget` (63) real tokens. Counted
///   with the loaded model ([vocabularyWithinTokens]); without a count only
///   a byte-safe prefix is sent ([vocabularyWithinBytes]), because
///   whisper.cpp itself would keep the LAST tokens, the least used terms.
/// - OpenAI and the own OpenAI-compatible endpoint: the `prompt` field.
///   whisper-1 and Whisper-based servers read only the last 224 tokens;
///   newer models document no limit. [vocabularyForCloudPrompt] keeps an
///   estimated [kCloudPromptVocabularyTokens], room left for the carried
///   context, which sits behind it.
/// - Deepgram and the system recogniser: `deepgramKeyterms` (50 terms,
///   500 bytes, front first).
/// - Parakeet: no prompt channel.
library;

import 'dart:convert' show utf8;

import 'vocabulary_terms.dart';

/// The units [stored] is cut in, and how a run of them is written: its
/// terms, or, for a text without a term separator (one free sentence), its
/// words, so such a prompt is still cut at a word and not dropped whole.
(List<String>, String Function(Iterable<String>)) _units(String stored) {
  final terms = vocabularyTerms(stored);
  if (terms.length == 1 && !stored.contains(RegExp(r'[,\n]'))) {
    return (
      stored.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList(),
      (words) => words.join(' '),
    );
  }
  return (terms, (t) => encodeVocabulary(t, style: stored));
}

/// Estimated tokens the vocabulary may take in a cloud `prompt`: 224
/// (whisper-1's window) minus about 60 for the carried context of up to 200
/// characters (`kContinuityContextChars`) and a margin.
const int kCloudPromptVocabularyTokens = 150;

/// Conservative token estimate without a tokenizer: one token per started
/// three UTF-8 bytes. Whisper's BPE averages about four characters per token
/// in Latin script and about one per character in CJK (three bytes), so the
/// estimate errs high.
int estimatedPromptTokens(String text) => (utf8.encode(text).length + 2) ~/ 3;

/// The vocabulary [stored] cut to its longest run of leading whole terms
/// for which [fits] holds, written in its own style. [fits] must be
/// monotone (a prefix of a fitting text fits).
Future<String> _leadingTerms(
  String stored,
  Future<bool> Function(String text) fits,
) async {
  final (terms, write) = _units(stored);
  String text(int n) => write(terms.take(n));
  if (terms.isEmpty) return '';
  if (await fits(text(terms.length))) return text(terms.length);
  var lo = 0; // fits
  var hi = terms.length; // does not fit
  while (hi - lo > 1) {
    final mid = (lo + hi) ~/ 2;
    if (await fits(text(mid))) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return text(lo);
}

/// [stored] cut to the leading whole terms that fit [budget] real tokens of
/// [countTokens] (the loaded Whisper model).
Future<String> vocabularyWithinTokens(
  String stored,
  int budget,
  Future<int> Function(String text) countTokens,
) => _leadingTerms(stored, (t) async => await countTokens(t) <= budget);

/// The leading whole terms of [stored] for which [fits] holds (sync).
String _leadingTermsSync(String stored, bool Function(String text) fits) {
  final (terms, write) = _units(stored);
  var n = 0;
  while (n < terms.length && fits(write(terms.take(n + 1)))) {
    n++;
  }
  return write(terms.take(n));
}

/// [stored] cut to the leading whole terms within [maxBytes] UTF-8 bytes.
/// A Whisper token is never shorter than one byte, so this never exceeds a
/// token budget of the same size.
String vocabularyWithinBytes(String stored, int maxBytes) =>
    _leadingTermsSync(stored, (t) => utf8.encode(t).length <= maxBytes);

/// [stored] cut for a cloud `prompt` to about
/// [kCloudPromptVocabularyTokens] estimated tokens, whole terms only.
String vocabularyForCloudPrompt(String stored) => _leadingTermsSync(
  stored,
  (t) => estimatedPromptTokens(t) <= kCloudPromptVocabularyTokens,
);
