/// Live counts of the editor's status line (#649): words, characters and
/// reading time of the whole text, and words and characters of the
/// selection.
library;

import 'package:flutter/services.dart' show TextSelection;

import '../utils/word_count.dart';

/// Characters as a reader counts them: Unicode code points, spaces and line
/// breaks included, so an emoji outside the basic plane counts once and not
/// as its two UTF-16 halves. One pass without allocating, so a two-million
/// character note is counted in a few milliseconds.
int computeCharacterCount(String text) {
  var count = 0;
  for (var i = 0; i < text.length; i++) {
    final cu = text.codeUnitAt(i);
    // A low surrogate right after a high one is the second half of one
    // character; a lone surrogate still counts.
    if (cu >= 0xDC00 &&
        cu <= 0xDFFF &&
        i > 0 &&
        _isHighSurrogate(text.codeUnitAt(i - 1))) {
      continue;
    }
    count++;
  }
  return count;
}

bool _isHighSurrogate(int cu) => cu >= 0xD800 && cu <= 0xDBFF;

/// Average silent reading speed the reading time is based on.
const int kReadingWordsPerMinute = 200;

/// What the status line shows, computed in one pass over text and selection.
class EditorTextStats {
  const EditorTextStats({
    required this.words,
    required this.characters,
    this.selectionWords = 0,
    this.selectionCharacters = 0,
  });

  /// Counts [text] and the part of it [selection] spans. [knownWords]
  /// stands in for the word count of the whole text where it is already
  /// known (the metadata index of a long recording).
  factory EditorTextStats.of(
    String text, {
    TextSelection? selection,
    int? knownWords,
  }) {
    var selWords = 0;
    var selChars = 0;
    if (selection != null && selection.isValid && !selection.isCollapsed) {
      final start = selection.start.clamp(0, text.length);
      final end = selection.end.clamp(0, text.length);
      if (end > start) {
        final part = text.substring(start, end);
        selWords = computeWordCountFast(part);
        selChars = computeCharacterCount(part);
      }
    }
    return EditorTextStats(
      words: knownWords ?? computeWordCountFast(text),
      characters: computeCharacterCount(text),
      selectionWords: selWords,
      selectionCharacters: selChars,
    );
  }

  static const EditorTextStats empty = EditorTextStats(words: 0, characters: 0);

  final int words;
  final int characters;
  final int selectionWords;
  final int selectionCharacters;

  /// Whether a non-empty range is selected.
  bool get hasSelection => selectionCharacters > 0;

  /// Rounded minutes at [kReadingWordsPerMinute]; 0 means under a minute.
  int get readingMinutes => (words / kReadingWordsPerMinute).round();

  @override
  bool operator ==(Object other) =>
      other is EditorTextStats &&
      other.words == words &&
      other.characters == characters &&
      other.selectionWords == selectionWords &&
      other.selectionCharacters == selectionCharacters;

  @override
  int get hashCode =>
      Object.hash(words, characters, selectionWords, selectionCharacters);

  @override
  String toString() =>
      'EditorTextStats($words words, $characters chars, '
      'selection $selectionWords/$selectionCharacters)';
}
