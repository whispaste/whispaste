import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/settings_provider.dart';
import '../../core/data/database.dart' show HistoryEntry;
import '../../core/data/history_providers.dart';
import '../../core/first_steps/first_steps_notifier.dart';
import '../../core/recording/recording_state.dart';

/// Feeds the "Erste Schritte" card from the app's existing observable state,
/// without touching the dictation pipeline itself:
///  - a dictation reaching `done` (the paste result and the target are on
///    the state);
///  - the saved recordings, for their target apps: when they load or change,
///    once the settings have loaded, and after a recording;
///  - a change of the custom vocabulary, and, once a recording ends, a
///    re-check of it (a change during a recording is held back).
/// A copied recording is reported by the copy actions themselves.
///
/// Mounted once in the app shell. It renders nothing.
class FirstStepsWatcher extends ConsumerWidget {
  const FirstStepsWatcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(firstStepsNotifierProvider.notifier);

    ref.listen<RecordingState>(recordingProvider, (previous, next) {
      if (!next.isDone || (previous?.isDone ?? false)) return;
      notifier.dictationFinished(
        pasted: next.pasted,
        toNote: ref.read(recordingTargetProvider) == RecordingTarget.quickNote,
        transcript: next.transcript ?? '',
      );
    });

    ref.listen<AsyncValue<List<HistoryEntry>>>(
      historyEntriesProvider,
      (previous, next) => notifier.reconcileHistory(),
    );
    ref.listen<bool>(
      settingsProvider.select(
        (s) => s.value?.onboarding.firstStepsArmed ?? false,
      ),
      (previous, armed) {
        if (armed) notifier.reconcileHistory();
      },
    );

    ref.listen<String>(
      settingsProvider.select((s) => s.value?.stt.customVocabulary ?? ''),
      (previous, next) => notifier.reconcileVocabulary(),
    );

    ref.listen<bool>(
      recordingProvider.select((s) => isDictationBusy(s.phase)),
      (previous, busy) {
        if (previous == true && !busy) {
          notifier.reconcileVocabulary();
          notifier.reconcileHistory();
        }
      },
    );

    return const SizedBox.shrink();
  }
}
