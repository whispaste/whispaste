/// The readiness list of the "Ausprobieren" page (#186): one pure function
/// decides, from the speech model, the microphone and the paste setup, which
/// of the three rows are ready and whether the closing page has to load a
/// model first. The page and the closing logic both read it, so they cannot
/// tell two different stories.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/settings_provider.dart';
import '../../services/paste/paste_capability_notifier.dart';
import '../../services/paste/paste_policy.dart';
import '../../services/paste/paster.dart';
import '../../services/permissions/mic_permission_notifier.dart';
import 'onboarding_download_provider.dart';
import 'onboarding_download_status.dart';
import 'stt_model_readiness.dart';

/// The speech recognition row: the selected engine's model.
enum SpeechReadiness { ready, loading, failed, missing }

/// The microphone row.
enum MicReadiness { ready, missing }

/// The paste row. Never blocks the try-out: the practice field receives the
/// text without the paste permission.
enum PasteReadiness {
  /// Auto-Paste is on and the platform can insert text.
  automatic,

  /// Auto-Paste is switched off: the text only lands in the clipboard.
  off,

  /// Auto-Paste is on, but the insert permission is missing or the platform
  /// cannot insert: for now the text only lands in the clipboard.
  clipboardOnly,
}

/// Snapshot of the three rows and what follows from them.
class OnboardingReadiness {
  const OnboardingReadiness({
    required this.speech,
    required this.speechFraction,
    required this.mic,
    required this.paste,
    required this.completionNeedsModel,
  });

  final SpeechReadiness speech;

  /// Download progress 0..1, meaningful while [speech] is loading.
  final double speechFraction;
  final MicReadiness mic;
  final PasteReadiness paste;

  /// Whether the closing page's main action must load a speech model: no
  /// model of any engine is usable, none is downloading and no cloud key is
  /// saved.
  final bool completionNeedsModel;

  /// Whether the try-out field is open: only the speech model locks it.
  bool get practiceUnlocked => speech == SpeechReadiness.ready;

  /// Whether a dictation can work right now. The paste row never counts.
  bool get canPractice => practiceUnlocked && mic == MicReadiness.ready;

  @override
  bool operator ==(Object other) =>
      other is OnboardingReadiness &&
      other.speech == speech &&
      other.speechFraction == speechFraction &&
      other.mic == mic &&
      other.paste == paste &&
      other.completionNeedsModel == completionNeedsModel;

  @override
  int get hashCode =>
      Object.hash(speech, speechFraction, mic, paste, completionNeedsModel);
}

/// The single source of the readiness list.
///
/// [gate] is the selected engine's practice gate, [fraction] its download
/// progress. [micMissing] is true when the microphone is denied or, once
/// checked, still not granted. [autoPaste] is the user's Auto-Paste setting,
/// [pasteCapable] whether the platform can insert text now. [modelUsable]
/// is true when any engine's model is installed or downloading, or a cloud
/// key is saved; it alone decides [OnboardingReadiness.completionNeedsModel].
OnboardingReadiness onboardingReadiness({
  required PracticeGate gate,
  double fraction = 0,
  required bool micMissing,
  required bool autoPaste,
  required bool pasteCapable,
  required bool modelUsable,
}) {
  return OnboardingReadiness(
    speech: switch (gate) {
      PracticeGate.open => SpeechReadiness.ready,
      PracticeGate.loading => SpeechReadiness.loading,
      PracticeGate.failed => SpeechReadiness.failed,
      PracticeGate.missing => SpeechReadiness.missing,
    },
    speechFraction: fraction.clamp(0, 1).toDouble(),
    mic: micMissing ? MicReadiness.missing : MicReadiness.ready,
    paste: !autoPaste
        ? PasteReadiness.off
        : pasteCapable
        ? PasteReadiness.automatic
        : PasteReadiness.clipboardOnly,
    completionNeedsModel: !modelUsable,
  );
}

/// Reads the live inputs of [onboardingReadiness]. [micChecked] says whether
/// the passive microphone check has answered; before that an unknown status
/// is not yet a missing microphone.
OnboardingReadiness watchOnboardingReadiness(
  WidgetRef ref, {
  bool micChecked = true,
}) {
  final micStatus = ref.watch(micPermissionNotifierProvider).status;
  final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
  final paste = ref.watch(pasteCapabilityNotifierProvider).capability;
  return onboardingReadiness(
    gate: ref.watch(onboardingPracticeGateProvider),
    fraction: ref.watch(onboardingDownloadStatusProvider).fraction,
    micMissing:
        micStatus == MicPermissionStatus.denied ||
        micChecked &&
            (micStatus == MicPermissionStatus.unknown ||
                micStatus == MicPermissionStatus.unresponsive),
    autoPaste: afterTranscriptionActionPastes(
      settings.afterTranscriptionAction,
    ),
    pasteCapable: paste == null || paste.status == PasteCapabilityStatus.ready,
    modelUsable: ref.watch(onboardingModelStepCanAdvanceProvider),
  );
}
