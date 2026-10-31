/// Name changes a free instruction made (2c): which capitalised words left
/// the text and which arrived in their place, paired by position.
library;

import '../../core/logging/app_logger.dart';
import 'smart_mode_fact_guard.dart';

final _nameLog = AppLogger('SmartModeNameChanges');

/// One line of the summary: "Müller → Meier", or an unpaired "– Müller" /
/// "+ Meier" when the other side has no partner.
class SmartModeNameChange {
  const SmartModeNameChange({this.from, this.to});

  final String? from;
  final String? to;
}

/// Name changes between [before] and [after]. Multiset difference of the name
/// words, so a repeated name counts each occurrence. Linear in the number of
/// words (GS-044): counts live in a map instead of repeated list removals.
List<SmartModeNameChange> smartModeNameChanges({
  required String before,
  required String after,
  required bool singleCapitalisedWordsAreNames,
}) {
  final old = smartModeNameWords(
    before,
    singleCapitalisedWordsAreNames: singleCapitalisedWordsAreNames,
  );
  final now = smartModeNameWords(
    after,
    singleCapitalisedWordsAreNames: singleCapitalisedWordsAreNames,
  );
  final removed = _unmatched(old, now);
  final added = _unmatched(now, old);
  final count = removed.length > added.length ? removed.length : added.length;
  return [
    for (var i = 0; i < count; i++)
      SmartModeNameChange(
        from: i < removed.length ? removed[i] : null,
        to: i < added.length ? added[i] : null,
      ),
  ];
}

/// The words of [words] that have no unused occurrence left in [other], in
/// their original order.
List<String> _unmatched(List<String> words, List<String> other) {
  final spare = <String, int>{};
  for (final word in other) {
    spare[word] = (spare[word] ?? 0) + 1;
  }
  final result = <String>[];
  for (final word in words) {
    final left = spare[word] ?? 0;
    if (left > 0) {
      spare[word] = left - 1;
    } else {
      result.add(word);
    }
  }
  return result;
}

/// [smartModeNameChanges] off the UI isolate once the texts are large
/// (GS-044). Returns null when the diff fails, so the caller can skip the
/// summary; a name toast never blocks the insert (DEV-163).
Future<List<SmartModeNameChange>?> checkSmartModeNameChanges({
  required String before,
  required String after,
  required bool singleCapitalisedWordsAreNames,
  Duration timeout = smartModeIsolateTimeout,
}) async {
  try {
    if (before.length + after.length > smartModeFactGuardIsolateThreshold) {
      // A hung isolate yields no summary (GS-045); the insert goes on.
      return await runGuardIsolate<List<SmartModeNameChange>?>(
        () => smartModeNameChanges(
          before: before,
          after: after,
          singleCapitalisedWordsAreNames: singleCapitalisedWordsAreNames,
        ),
        timeout,
      ).catchError((Object _) {
        _nameLog.warning('Name-change summary timed out or failed');
        return null;
      });
    }
    return smartModeNameChanges(
      before: before,
      after: after,
      singleCapitalisedWordsAreNames: singleCapitalisedWordsAreNames,
    );
  } on Object catch (error) {
    _nameLog.warning('Name-change summary failed (${error.runtimeType})');
    return null;
  }
}

/// Keywords that mark a free instruction as a translation (2c: no name toast,
/// because a translation changes names legitimately). Kept in this one place.
const smartModeTranslationKeywords = <String>[
  // German
  'übersetz', 'ins englische', 'ins deutsche', 'ins französische',
  'ins spanische', 'ins portugiesische', 'ins russische', 'ins hebräische',
  // English
  'translate', 'into english', 'into german', 'into french', 'into spanish',
  'into portuguese', 'into russian', 'into hebrew',
  // Spanish
  'traduce', 'traduzca', 'al inglés', 'al alemán',
  // Portuguese
  'traduza', 'para o inglês', 'para o alemão',
  // Russian
  'переведи', 'перевод', 'на английский', 'на немецкий',
  // Hebrew
  'תרגם', 'לאנגלית', 'לגרמנית',
];

/// Whether [instruction] asks for a translation (see
/// [smartModeTranslationKeywords]). Case-insensitive substring match.
bool isTranslationInstruction(String instruction) {
  final lower = instruction.toLowerCase();
  return smartModeTranslationKeywords.any(lower.contains);
}

/// Up to [maxPairs] changes joined with ", ", then "+N" for the rest.
String formatNameChangeSummary(
  List<SmartModeNameChange> changes, {
  int maxPairs = 3,
}) {
  String line(SmartModeNameChange c) => switch ((c.from, c.to)) {
    (final from?, final to?) => '$from → $to',
    (final from?, null) => '– $from',
    (null, final to?) => '+ $to',
    _ => '',
  };
  final shown = changes.take(maxPairs).map(line).where((s) => s.isNotEmpty);
  final rest = changes.length - maxPairs;
  return [...shown, if (rest > 0) '+$rest'].join(', ');
}
