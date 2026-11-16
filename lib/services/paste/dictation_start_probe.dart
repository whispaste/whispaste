/// Reads the text in front of the caret while the dictation is still being
/// transcribed, so [adaptDictationStart] costs the paste nothing (#401).
///
/// The read starts when the recording stops and runs next to the recognition.
/// That is what keeps the slow case off the hotkey path: Linux needs about half
/// a second to find the focused element in the AT-SPI tree. A read that is not
/// done when the text is ready gets [kDictationStartWait] more, then the text
/// goes in unchanged.
///
/// Privacy: the text stays in memory and is never logged. Password fields are
/// refused natively.
library;

import 'dart:async';

import '../../core/logging/app_logger.dart';
import '../replacements/target_field_span.dart';
import 'dictation_start.dart';

final _log = AppLogger('DictationStart');

/// The longest a finished transcript waits for the field. The paste never
/// waits longer, whatever the target app does.
const Duration kDictationStartWait = Duration(milliseconds: 100);

/// Reads the text in front of the caret of the focused field.
abstract interface class CaretTextReader {
  Future<TargetFieldRead> readBeforeCaret(int chars);
}

class DictationStartProbe {
  DictationStartProbe.start(
    CaretTextReader reader,
    Future<Iterable<String>> Function() protectedTerms,
  ) : _context = _read(reader, protectedTerms);

  final Future<_FieldContext?> _context;

  /// [text] fitted to the field, or [text] itself when the field is unreadable,
  /// has no caret or does not answer within [wait].
  Future<String> fit(
    String text, {
    String? languageCode,
    Duration wait = kDictationStartWait,
  }) async {
    final context = await _context.timeout(wait, onTimeout: () => null);
    if (context == null) return text;
    return adaptDictationStart(
      text,
      before: context.before,
      languageCode: languageCode,
      protectedTerms: context.terms,
    );
  }

  static Future<_FieldContext?> _read(
    CaretTextReader reader,
    Future<Iterable<String>> Function() protectedTerms,
  ) async {
    try {
      // Both at once, and awaited together: an error of the one that finishes
      // first must not go unhandled while the other is still running.
      final (read, terms) = await (
        reader.readBeforeCaret(kDictationStartContextChars),
        protectedTerms(),
      ).wait;
      final before = read.text;
      if (before == null || !read.hasCaret) return null;
      return _FieldContext(before, terms.toSet());
    } on Object catch (e) {
      // Without the dictionary a term could lose its spelling, so a failure
      // here means no change at all. The error never carries field contents.
      _log.debug('Dictation start not fitted (${e.runtimeType})');
      return null;
    }
  }
}

class _FieldContext {
  const _FieldContext(this.before, this.terms);

  final String before;
  final Set<String> terms;
}
