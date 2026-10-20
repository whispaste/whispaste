import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/language_cycle.dart';
import '../core/config/settings_provider.dart';
import '../core/recording/recording_state.dart';

/// Result of the last press of the "next favorite language" hotkey.
class LanguageCycleFeedback {
  const LanguageCycleFeedback({
    required this.language,
    required this.serial,
    this.duringRecording = false,
  });

  /// The press happened while a recording was running. The new language then
  /// applies from the next recording only (SW-03), and the toast says so.
  final bool duringRecording;

  /// The language that is now active, or `null` when there is no favorite to
  /// switch to.
  final String? language;

  /// Counts up on every press, so a repeated press with the same result shows
  /// its feedback again.
  final int serial;
}

/// Switches the dictation language to the next favorite and reports the result
/// through [languageCycleFeedbackProvider].
class LanguageCycleController extends Notifier<LanguageCycleFeedback?> {
  @override
  LanguageCycleFeedback? build() => null;

  Future<void> cycle() async {
    final stt = (ref.read(settingsProvider).value ?? AppSettings.defaults).stt;
    final next = nextFavoriteLanguage(
      current: stt.language,
      favorites: stt.favoriteLanguages,
    );
    final serial = (state?.serial ?? 0) + 1;
    final duringRecording =
        ref.read(recordingPhaseProvider) != RecordingPhase.idle;
    if (next == null) {
      state = LanguageCycleFeedback(language: null, serial: serial);
      return;
    }
    await ref
        .read(settingsProvider.notifier)
        .updateSettings(
          (s) => s.copyWithSections(stt: s.stt.copyWith(language: next)),
        );
    state = LanguageCycleFeedback(
      language: next,
      serial: serial,
      duringRecording: duringRecording,
    );
  }
}

/// Feedback for the "next favorite language" hotkey, read by the app shell to
/// show a toast.
final languageCycleFeedbackProvider =
    NotifierProvider<LanguageCycleController, LanguageCycleFeedback?>(
      LanguageCycleController.new,
    );
