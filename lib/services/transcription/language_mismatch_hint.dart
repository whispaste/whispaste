/// Hand-off for the wrong-language hint (9.10).
///
/// The orchestrator publishes a hint after a transcription whose detected
/// language differs from the fixed setting; the recording widget shows it and
/// clears it, the same way the paste-failure event is handed over.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A transcription heard [detected] while the setting is [configured].
///
/// Both are whisper codes such as `de`. A new instance per event, so a repeated
/// mismatch fires again after the previous hint was cleared.
class LanguageMismatchHint {
  const LanguageMismatchHint({
    required this.detected,
    required this.configured,
  });

  final String detected;
  final String configured;
}

class LanguageMismatchHintNotifier extends Notifier<LanguageMismatchHint?> {
  @override
  LanguageMismatchHint? build() => null;

  void show(LanguageMismatchHint hint) => state = hint;

  void clear() => state = null;
}

final languageMismatchHintProvider =
    NotifierProvider<LanguageMismatchHintNotifier, LanguageMismatchHint?>(
      LanguageMismatchHintNotifier.new,
    );
