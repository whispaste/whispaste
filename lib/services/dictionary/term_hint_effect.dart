import '../../core/config/settings_enums.dart';

/// What a dictionary term does for the speech engine that is active right
/// now (matrix 4.1). Terms are never shown as "active" for an engine that
/// cannot use them: that would be the same "looks available but isn't" trap
/// the settings page avoids for the language picker.
enum TermHintEffect {
  /// The terms are handed to the recognizer as a prompt: whisper.cpp's
  /// `initial_prompt` for on-device Whisper, the `prompt` field of the
  /// OpenAI transcription endpoint. The engine may favour these spellings
  /// but is not forced to produce them.
  promptHint,

  /// The engine has no prompt channel (on-device Parakeet, Deepgram here).
  /// Only exact and similarity replacements change the text.
  replacementOnly,
}

/// Maps the active provider and on-device engine to its [TermHintEffect].
///
/// Keep in sync with the two places that read the vocabulary:
/// `SttServerStateNotifier` (on-device Whisper) and `OpenAiTranscriber`
/// (OpenAI). Any new engine with a prompt channel must be added here.
TermHintEffect termHintEffectFor({
  required SttProviderType provider,
  required OnDeviceEngine engine,
}) {
  return switch (provider) {
    SttProviderType.openAI => TermHintEffect.promptHint,
    SttProviderType.onDevice =>
      engine == OnDeviceEngine.whisper
          ? TermHintEffect.promptHint
          : TermHintEffect.replacementOnly,
    SttProviderType.deepgram => TermHintEffect.replacementOnly,
  };
}
