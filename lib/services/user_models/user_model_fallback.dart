/// Which checked model takes over when a user's own model fails (#1789).
///
/// Pure rules; the notifier applies them to the settings. The order is:
/// the catalog choice the user had in use before switching to their own model
/// (remembered in `user_models.json`), if it is still installed; otherwise
/// the best installed Whisper model, then Parakeet, then Apple's engine.
/// With nothing installed there is no fallback, and the recording waits as
/// pending audio for a retry like any other failed transcription.
library;

import '../../core/config/settings_enums.dart';
import '../path_service.dart' show isUserModelId;
import 'user_model.dart';

/// The catalog Whisper models, best first.
const List<String> kWhisperFallbackOrder = [
  'whisper-large-v3-turbo',
  'whisper-medium',
  'whisper-small',
];

/// Persisted engine value of a user's own sherpa-onnx model. Its own
/// whisper.cpp models run on the `whisper` engine with a `user-…` id.
const String kUserModelEngineValue = 'user_model';

/// Whether [choice] names a user's own model rather than a catalog one.
bool isUserModelChoice(SpeechFallbackChoice choice) =>
    choice.engine == kUserModelEngineValue ||
    (choice.engine == OnDeviceEngine.whisper.value &&
        isUserModelId(choice.modelId));

/// The fallback for a failed speech model, or null when none is installed.
SpeechFallbackChoice? pickSpeechFallback({
  required SpeechFallbackChoice? remembered,
  required Set<String> installedWhisper,
  required bool parakeetInstalled,
  required bool systemReady,
}) {
  bool usable(SpeechFallbackChoice c) {
    if (isUserModelChoice(c)) return false;
    // An engine value this version does not know is never a safe target.
    if (OnDeviceEngine.fromValue(c.engine).value != c.engine) return false;
    return switch (OnDeviceEngine.fromValue(c.engine)) {
      OnDeviceEngine.whisper => installedWhisper.contains(c.modelId),
      OnDeviceEngine.parakeet => parakeetInstalled,
      OnDeviceEngine.system => systemReady,
      // Already refused by isUserModelChoice above.
      OnDeviceEngine.userModel => false,
    };
  }

  if (remembered != null && usable(remembered)) return remembered;
  for (final id in kWhisperFallbackOrder) {
    if (installedWhisper.contains(id)) {
      return SpeechFallbackChoice(
        engine: OnDeviceEngine.whisper.value,
        modelId: id,
      );
    }
  }
  // Parakeet and Apple's engine ignore the Whisper id; keep a catalog one so
  // switching back to Whisper later lands on it, never on a user model.
  final keep = remembered?.modelId ?? '';
  final keepModel = isUserModelId(keep) ? '' : keep;
  if (parakeetInstalled) {
    return SpeechFallbackChoice(
      engine: OnDeviceEngine.parakeet.value,
      modelId: keepModel,
    );
  }
  if (systemReady) {
    return SpeechFallbackChoice(
      engine: OnDeviceEngine.system.value,
      modelId: keepModel,
    );
  }
  return null;
}

/// The catalog choice in use right now, worth remembering before switching
/// to a user model; null when the current choice is a user model itself.
SpeechFallbackChoice? currentCatalogSpeechChoice({
  required String engine,
  required String whisperModelId,
}) {
  final choice = SpeechFallbackChoice(engine: engine, modelId: whisperModelId);
  return isUserModelChoice(choice) ? null : choice;
}

/// Whether a failure of a user model in use should hand the recording to the
/// fallback. A cancel is the user's own stop, not a model failure.
bool userModelFailureFallsBack({required bool cancelled}) => !cancelled;
