/// Text hygiene for a finished transcript, the same for every speech engine.
///
/// [applyTranscriptHygiene] runs in the orchestrator after every engine
/// (whisper, Parakeet, OpenAI, Deepgram), so an engine cannot skip a rule
/// that another one applies. Each step is idempotent: the whisper notifier
/// runs the same steps on its own output, and a second pass changes nothing.
library;

import 'transcript_hallucination_filter.dart';

/// Whisper-style sound annotations in square brackets: `[Musik]`,
/// `[BLANK_AUDIO]`, `[ Pause ]`.
final _bracketTag = RegExp(r'\[[^\]]*\]');
final _whitespaceRun = RegExp(r'\s+');

/// A repeated sentence collapses only from this size on: 4 words or 20
/// characters, whichever is reached first. A short interjection said three
/// times ("Ja. Ja. Ja.") is speech; a long sentence repeated three times is
/// the decoder looping.
const _collapseMinWords = 4;
const _collapseMinChars = 20;

/// The full hygiene for a finished transcript from any engine. Returns the
/// empty string for a transcript that is only non-speech, so the caller takes
/// the same path as a blank recording.
String applyTranscriptHygiene(String transcript) {
  final cleaned = stripNonSpeechMarkers(transcript.trim());
  if (isNonSpeechTranscript(cleaned)) return '';
  return collapseRepeatedSentences(cleaned);
}

/// Removes bracket tags and collapses the whitespace they leave behind.
/// Round brackets stay: a user may dictate parenthesised text, whereas square
/// brackets practically never occur in spoken input.
String stripNonSpeechMarkers(String text) {
  if (text.isEmpty) return text;
  return text
      .replaceAll(_bracketTag, ' ')
      .replaceAll(_whitespaceRun, ' ')
      .trim();
}

/// Keeps at most two copies of a sentence repeated back to back, but only for
/// sentences of [_collapseMinWords] words or [_collapseMinChars] characters.
/// Returns [text] unchanged when nothing was collapsed.
String collapseRepeatedSentences(String text) {
  if (text.length < _collapseMinChars) return text;

  final sentences = <String>[];
  final buf = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    buf.writeCharCode(text.codeUnitAt(i));
    final c = text[i];
    if (c == '.' || c == '?' || c == '!') {
      sentences.add(buf.toString().trim());
      buf.clear();
    }
  }
  final trailing = buf.toString().trim();
  if (trailing.isNotEmpty) sentences.add(trailing);

  if (sentences.length < 3) return text;

  final result = <String>[];
  var prevSentence = '';
  var runCount = 0;
  var collapsed = false;

  for (final s in sentences) {
    if (s == prevSentence && _isCollapsible(s)) {
      runCount++;
      if (runCount < 3) {
        result.add(s);
      } else {
        collapsed = true;
      }
    } else {
      prevSentence = s;
      runCount = 1;
      result.add(s);
    }
  }

  return collapsed ? result.join(' ') : text;
}

bool _isCollapsible(String sentence) {
  if (sentence.length >= _collapseMinChars) return true;
  return sentence.split(_whitespaceRun).length >= _collapseMinWords;
}
