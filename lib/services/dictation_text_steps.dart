import '../core/config/settings_provider.dart';
import 'text_transforms.dart' as transforms;
import 'voice_line_breaks.dart';
import 'voice_punctuation.dart';

/// The text steps that turn a whitespace-cleaned transcript into the text a
/// dictation saves to history, before Smart Mode: filler words, spoken
/// punctuation, spoken line breaks, dictionary replacements, in that order.
///
/// The live pipeline and the recovery of a parked raw transcript both run
/// [apply], so a recovered entry gets the same text as a normal dictation.
/// The flags are a snapshot of the settings at dictation time; a parked
/// dictation stores them, so a later settings change does not alter it.
class DictationTextSteps {
  const DictationTextSteps({
    required this.removeFillerWords,
    required this.spokenPunctuation,
    required this.voiceLineBreaks,
    required this.textReplacements,
  });

  /// Steps as [settings] enable them. [textReplacements] is false where the
  /// pipeline skips the dictionary (the onboarding sandbox).
  factory DictationTextSteps.fromSettings(
    AppSettings settings, {
    bool textReplacements = true,
  }) => DictationTextSteps(
    removeFillerWords: settings.stt.removeFillerWords,
    spokenPunctuation: settings.stt.spokenPunctuation,
    voiceLineBreaks: settings.stt.voiceLineBreaks,
    textReplacements:
        textReplacements && settings.behavior.textReplacementsEnabled,
  );

  /// Reads [toJson] output. Returns null for anything else, so a corrupted
  /// value never fails the record that holds it.
  static DictationTextSteps? tryParse(Object? json) {
    if (json is! Map) return null;
    bool flag(String key) => json[key] == true;
    return DictationTextSteps(
      removeFillerWords: flag('removeFillerWords'),
      spokenPunctuation: flag('spokenPunctuation'),
      voiceLineBreaks: flag('voiceLineBreaks'),
      textReplacements: flag('textReplacements'),
    );
  }

  final bool removeFillerWords;
  final bool spokenPunctuation;
  final bool voiceLineBreaks;
  final bool textReplacements;

  Map<String, Object?> toJson() => {
    'removeFillerWords': removeFillerWords,
    'spokenPunctuation': spokenPunctuation,
    'voiceLineBreaks': voiceLineBreaks,
    'textReplacements': textReplacements,
  };

  /// Runs the enabled steps on [cleaned]. Spoken punctuation goes before
  /// line breaks, so "comma" next to "new paragraph" resolves first; the
  /// replacements run last, so a trigger interrupted by a filler word still
  /// fires and Smart Mode sees the corrected terms.
  Future<String> apply(
    String cleaned, {
    required String languageCode,
    required Future<String> Function(String text) applyReplacements,
  }) async {
    var text = cleaned;
    if (removeFillerWords) {
      text = transforms.removeFillerWords(text, languageCode: languageCode);
    }
    if (spokenPunctuation) {
      text = applyVoicePunctuation(text, languageCode: languageCode);
    }
    if (voiceLineBreaks) {
      text = applyVoiceLineBreaks(text, languageCode: languageCode);
    }
    if (textReplacements) text = await applyReplacements(text);
    return text;
  }
}
