import 'package:flutter/services.dart';

final _wordChar = RegExp(r'[\p{L}\p{N}]', unicode: true);
final _noSpaceAfter = RegExp(r'[\s(\[{"„“‚«»¿¡/-]');
final _noSpaceBefore = RegExp(r'^[\s.,;:!?…)\]}»”"%]');

/// Inserts a dictated [transcript] at [value]'s selection, replacing any
/// selected range, and adds the word gap a typist would (XP-5-11): a space
/// before it when it lands right after a word or sentence end, and one after
/// it when the next character starts a word. The caret ends after the
/// transcript, so a follow-up dictation continues the sentence.
TextEditingValue insertDictation(TextEditingValue value, String transcript) {
  final text = value.text;
  final selection = value.selection;
  // A selection can point past the text when it is stale; clamp it so that the
  // insert never throws and the transcript is never lost. Clamping keeps the
  // order start <= end.
  final start = selection.isValid
      ? _withinText(selection.start, text)
      : text.length;
  final end = selection.isValid
      ? _withinText(selection.end, text)
      : text.length;
  if (transcript.isEmpty) {
    return value.copyWith(text: text.replaceRange(start, end, ''));
  }
  final before = start > 0 ? text[start - 1] : '';
  final after = end < text.length ? text[end] : '';
  final lead =
      before.isNotEmpty &&
          !_noSpaceAfter.hasMatch(before) &&
          !_noSpaceBefore.hasMatch(transcript)
      ? ' '
      : '';
  final trail =
      _wordChar.hasMatch(after) && !RegExp(r'\s$').hasMatch(transcript)
      ? ' '
      : '';
  final inserted = '$lead$transcript';
  return TextEditingValue(
    text: text.replaceRange(start, end, '$inserted$trail'),
    selection: TextSelection.collapsed(offset: start + inserted.length),
  );
}

int _withinText(int offset, String text) =>
    offset < 0 ? 0 : (offset > text.length ? text.length : offset);
