/// Riverpod state of the "Erste Schritte" card (see `first_steps.dart` for the
/// rules). Writes go to the settings; the watcher in
/// `lib/features/first_steps/first_steps_watcher.dart` feeds it events.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/settings_provider.dart';
import '../config/settings_sections.dart';
import '../data/history_providers.dart';
import '../recording/recording_state.dart';
import 'first_steps.dart';

/// What the card shows, derived from the settings and the recording state.
class FirstStepsView {
  const FirstStepsView({
    required this.visible,
    required this.done,
    required this.canShowAgain,
  });

  final bool visible;
  final Set<FirstStepsItem> done;
  final bool canShowAgain;
}

/// The celebration flag (`true` while the calm success state is up). Nothing
/// else is in memory: progress and dismissal live in the settings.
class FirstStepsNotifier extends Notifier<bool> {
  Timer? _celebration;

  @override
  bool build() {
    ref.onDispose(() => _celebration?.cancel());
    return false;
  }

  /// A dictation reached its end state. Called once per finished dictation,
  /// from the transition into `done`.
  void dictationFinished({
    required bool pasted,
    required bool toNote,
    required String transcript,
  }) => _update(
    (done) => firstStepsAfterDictation(
      done: done,
      pasted: pasted,
      toNote: toNote,
      transcript: transcript,
    ),
  );

  /// Reads the target apps of the saved recordings. Called when they load or
  /// change, when the settings load and when a recording ends, so whichever
  /// arrives last still confirms the first step, also for dictations made
  /// before the card learned this rule.
  void reconcileHistory() {
    final entries = ref.read(historyEntriesProvider).value;
    if (entries == null) return;
    _update(
      (done) => firstStepsAfterHistory(
        done: done,
        targetApps: entries.map((e) => e.targetApp),
      ),
    );
  }

  /// A recording was copied from the Übersicht or the Aufnahmen page.
  void recordingCopied() => _update(firstStepsAfterCopy);

  /// The custom vocabulary may have changed. Reads the current value, so a
  /// call while a recording runs is dropped and repeated on idle by the
  /// watcher.
  void reconcileVocabulary() {
    final vocabulary =
        ref.read(settingsProvider).value?.stt.customVocabulary ?? '';
    _update(
      (done) =>
          firstStepsAfterVocabulary(done: done, customVocabulary: vocabulary),
    );
  }

  /// The user closed the card. Progress is kept.
  Future<void> dismiss() => _writeOnboarding(
    (onboarding) => onboarding.copyWith(firstStepsDismissed: true),
  );

  /// "Neu anzeigen" in Settings: shows the card again, keeps every
  /// confirmed item.
  Future<void> showAgain() => _writeOnboarding(
    (onboarding) => onboarding.copyWith(firstStepsDismissed: false),
  );

  void _update(Set<FirstStepsItem> Function(Set<FirstStepsItem>) change) {
    final onboarding = ref.read(settingsProvider).value?.onboarding;
    if (onboarding == null || !onboarding.firstStepsArmed) return;
    if (_isBusy()) return;
    final before = parseFirstStepsDone(onboarding.firstStepsDone);
    final after = change(before);
    if (after.length == before.length) return;
    unawaited(
      _writeOnboarding(
        (current) =>
            current.copyWith(firstStepsDone: serializeFirstStepsDone(after)),
      ),
    );
    if (!firstStepsAllDone(before) &&
        firstStepsAllDone(after) &&
        !onboarding.firstStepsDismissed) {
      _startCelebration();
    }
  }

  Future<void> _writeOnboarding(
    OnboardingSettings Function(OnboardingSettings) change,
  ) async {
    final onboarding = ref.read(settingsProvider).value?.onboarding;
    if (onboarding == null || !onboarding.firstStepsArmed) return;
    if (_isBusy()) return;
    await ref
        .read(settingsProvider.notifier)
        .updateSettings(
          (s) => s.copyWithSections(onboarding: change(s.onboarding)),
        );
  }

  void _startCelebration() {
    _celebration?.cancel();
    state = true;
    _celebration = Timer(kFirstStepsCelebration, () => state = false);
  }

  bool _isBusy() => isDictationBusy(ref.read(recordingProvider).phase);
}

final firstStepsNotifierProvider = NotifierProvider<FirstStepsNotifier, bool>(
  FirstStepsNotifier.new,
);

/// The card's view model. Watches the settings and the recording phase, so
/// the card is hidden for the whole duration of a recording.
final firstStepsViewProvider = Provider<FirstStepsView>((ref) {
  final onboarding = ref.watch(
    settingsProvider.select(
      (s) => s.value?.onboarding ?? OnboardingSettings.defaults,
    ),
  );
  final busy = ref.watch(
    recordingProvider.select((s) => isDictationBusy(s.phase)),
  );
  final celebrating = ref.watch(firstStepsNotifierProvider);
  final done = parseFirstStepsDone(onboarding.firstStepsDone);
  return FirstStepsView(
    visible: firstStepsVisible(
      armed: onboarding.firstStepsArmed,
      dismissed: onboarding.firstStepsDismissed,
      busy: busy,
      done: done,
      celebrating: celebrating,
    ),
    done: done,
    canShowAgain: firstStepsCanShowAgain(
      armed: onboarding.firstStepsArmed,
      done: done,
    ),
  );
});
