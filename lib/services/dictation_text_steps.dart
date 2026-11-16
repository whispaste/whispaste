import '../core/config/settings_provider.dart';
import 'dictionary/term_hint_effect.dart';
import 'dictionary/term_similarity.dart';
import 'itn/itn_pipeline.dart';
import 'text_transforms.dart' as transforms;
import 'voice_line_breaks.dart';
import 'voice_punctuation.dart';

/// Applies the dictionary replacements to a text; [cascade] off makes every
/// rule match only the text it is given (setting
/// [BehaviorSettings.replacementsCascade], #1004).
typedef ReplacementsApplier =
    Future<String> Function(String text, {bool cascade});

/// The text steps that turn a whitespace-cleaned transcript into the text a
/// dictation saves to history, before Smart Mode: filler words, spoken
/// punctuation, spoken line breaks, written forms, dictionary replacements,
/// in that order.
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
    this.replacementsCascade = true,
    this.writtenForms = const {},
    this.termSimilarity = false,
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
    replacementsCascade: settings.behavior.replacementsCascade,
    writtenForms: _writtenFormsOf(settings),
    termSimilarity:
        textReplacements &&
        settings.behavior.textReplacementsEnabled &&
        settings.behavior.termSimilarityEnabled &&
        termHintEffectFor(
              provider: settings.sttProviderType,
              engine: settings.onDeviceEngine,
            ) ==
            TermHintEffect.replacementOnly,
  );

  /// Reads [toJson] output. Returns null for anything else, so a corrupted
  /// value never fails the record that holds it. A record without written
  /// forms (stored before the stage existed) runs without them.
  static DictationTextSteps? tryParse(Object? json) {
    if (json is! Map) return null;
    bool flag(String key) => json[key] == true;
    return DictationTextSteps(
      removeFillerWords: flag('removeFillerWords'),
      spokenPunctuation: flag('spokenPunctuation'),
      voiceLineBreaks: flag('voiceLineBreaks'),
      textReplacements: flag('textReplacements'),
      // Records parked before #1004 have no key: the cascade was always on.
      replacementsCascade: json['replacementsCascade'] != false,
      writtenForms: _writtenFormsFromJson(json['writtenForms']),
    );
  }

  final bool removeFillerWords;
  final bool spokenPunctuation;
  final bool voiceLineBreaks;
  final bool textReplacements;

  /// Whether the replacements build on each other (the cascade).
  final bool replacementsCascade;

  /// The written-form kinds that run. Empty when the master switch is off.
  final Set<WrittenFormKind> writtenForms;

  /// Strict similarity matching of the dictionary terms (#147): on only for
  /// an engine without a prompt hint, and when the user has not switched it
  /// off. Not stored with a parked raw transcript: its recovery has no
  /// vocabulary at hand and runs without it.
  final bool termSimilarity;

  Map<String, Object?> toJson() => {
    'removeFillerWords': removeFillerWords,
    'spokenPunctuation': spokenPunctuation,
    'voiceLineBreaks': voiceLineBreaks,
    'textReplacements': textReplacements,
    'replacementsCascade': replacementsCascade,
    'writtenForms': [
      for (final kind in WrittenFormKind.values)
        if (writtenForms.contains(kind)) kind.name,
    ],
  };

  /// Runs the enabled steps on [cleaned]. Spoken punctuation goes before
  /// line breaks, so "comma" next to "new paragraph" resolves first; written
  /// forms follow the line breaks and come before the replacements, so a
  /// user's own replacement always has the last word, and a trigger
  /// interrupted by a filler word still fires and Smart Mode sees the
  /// corrected terms.
  Future<String> apply(
    String cleaned, {
    required String languageCode,
    required ReplacementsApplier applyReplacements,
    List<String> terms = const [],
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
    if (writtenForms.isNotEmpty) {
      text = applyWrittenForms(
        text,
        languageCode: languageCode,
        enabled: writtenForms,
      );
    }
    if (textReplacements) {
      text = await applyReplacements(text, cascade: replacementsCascade);
    }
    if (textReplacements && termSimilarity) {
      text = applyTermSimilarity(text, terms);
    }
    return text;
  }

  static Set<WrittenFormKind> _writtenFormsOf(AppSettings settings) {
    final stt = settings.stt;
    if (!stt.writtenForms.enabled) return const {};
    return {
      if (stt.writtenForms.email) WrittenFormKind.email,
      if (stt.writtenForms.url) WrittenFormKind.url,
      if (stt.writtenForms.date) WrittenFormKind.date,
      if (stt.writtenForms.time) WrittenFormKind.time,
      if (stt.writtenForms.money) WrittenFormKind.money,
    };
  }

  static Set<WrittenFormKind> _writtenFormsFromJson(Object? value) {
    if (value is! List) return const {};
    final byName = WrittenFormKind.values.asNameMap();
    return {
      for (final name in value)
        if (name is String && byName.containsKey(name)) byName[name]!,
    };
  }
}
