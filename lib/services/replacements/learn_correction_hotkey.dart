/// The "Learn correction" hotkey (#934): the user selects the corrected word
/// in another app and presses the hotkey. WhisPaste copies the selection
/// (posted copy shortcut, clipboard restored afterwards), finds the place in
/// the last dictation it corrects and proposes the pair in the Dictionary at
/// once. Works the same on macOS (including the Mac App Store build, which
/// may post the copy shortcut), Windows and Linux.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/settings_provider.dart';
import '../../core/data/database.dart';
import '../../core/logging/app_logger.dart';
import '../../core/recording/recording_state.dart';
import '../desktop_paste/desktop_paste_controller.dart';
import '../paste/repaste_service.dart' show lastDictationTextProvider;
import '../selection_edit/selection_edit_service.dart';
import 'correction_learning_service.dart';
import 'correction_signal.dart';
import 'selection_correction_match.dart';

final _log = AppLogger('LearnCorrection');

/// What one press of the hotkey did; the overlay says it in a short pill.
enum LearnCorrectionOutcome {
  /// A replacement waits for a decision in the Dictionary.
  proposed,

  /// The selection fits no place in the last dictation (or there is none).
  nothingFound,

  /// Nothing was selected, or the copy could not be done.
  noSelection,

  /// "Learn from corrections" is switched off; nothing was read.
  learningOff,
}

/// The last outcome with a running number, so two equal outcomes in a row
/// still reach the listeners (overlay pill, Dictionary list).
typedef LearnCorrectionFeedback = ({int seq, LearnCorrectionOutcome outcome});

class LearnCorrectionFeedbackNotifier
    extends Notifier<LearnCorrectionFeedback?> {
  @override
  LearnCorrectionFeedback? build() => null;

  void raise(LearnCorrectionOutcome outcome) =>
      state = (seq: (state?.seq ?? 0) + 1, outcome: outcome);
}

final learnCorrectionFeedbackProvider =
    NotifierProvider<LearnCorrectionFeedbackNotifier, LearnCorrectionFeedback?>(
      LearnCorrectionFeedbackNotifier.new,
    );

/// Reads the selection of the app in front. `null` where the platform has no
/// paste path (then the hotkey says "no selection"). Tests override it.
final learnCorrectionSelectionReaderProvider = Provider<SelectionReader?>((
  ref,
) {
  final controller = ref.watch(desktopPasteControllerProvider);
  if (controller == null) return null;
  return SelectionReader(
    copy: (delay) => controller.copySelection(delay: delay),
    clipboard: SystemSelectionClipboard(controller),
  );
});

/// The one info line per press: app and result, never text.
String learnCorrectionLogLine({
  required String? app,
  required LearnCorrectionOutcome outcome,
}) {
  final raw = (app ?? '').trim();
  final name = raw.isEmpty ? 'unknown' : raw.split(RegExp(r'[/\\]')).last;
  return 'Learn correction hotkey: app=$name, result=${outcome.name}';
}

class LearnCorrectionHotkeyService {
  LearnCorrectionHotkeyService(this.ref);

  final Ref ref;
  bool _running = false;

  /// Handles one press. Never throws; the outcome goes to
  /// [learnCorrectionFeedbackProvider] and one log line.
  Future<void> learnFromSelection() async {
    // A second press while the first still copies would read our own
    // sentinel; a running dictation owns the clipboard.
    if (_running || isDictationBusy(ref.read(recordingPhaseProvider))) {
      _log.info('Learn correction hotkey: ignored (busy)');
      return;
    }
    _running = true;
    String? app;
    var outcome = LearnCorrectionOutcome.nothingFound;
    try {
      final settings = ref.read(settingsProvider).value ?? AppSettings.defaults;
      if (!settings.behavior.correctionLearningEnabled) {
        outcome = LearnCorrectionOutcome.learningOff;
        return;
      }
      app = await _frontApp();
      final reader = ref.read(learnCorrectionSelectionReaderProvider);
      final read = reader == null ? null : await reader.read();
      if (read is! SelectionReadOk) {
        outcome = LearnCorrectionOutcome.noSelection;
        return;
      }
      final db = ref.read(historyDatabaseProvider);
      final dictation =
          ref.read(lastDictationTextProvider) ?? await db.latestEntryText();
      final match = dictation == null
          ? null
          : matchSelectionToDictation(read.text, dictation);
      if (match == null) return;
      final proposed = await ref
          .read(correctionLearningServiceProvider)
          .recordSignal(
            CorrectionSignal(
              sourceText: match.sourceText,
              targetText: match.targetText,
              contextBefore: match.contextBefore,
              timestamp: DateTime.now(),
              source: CorrectionSignalSource.selectionHotkey,
            ),
            db,
          );
      if (proposed > 0) outcome = LearnCorrectionOutcome.proposed;
    } on Object catch (e) {
      _log.info('Learn correction hotkey: ended early (${e.runtimeType})');
    } finally {
      _running = false;
      _log.info(learnCorrectionLogLine(app: app, outcome: outcome));
      ref.read(learnCorrectionFeedbackProvider.notifier).raise(outcome);
    }
  }

  /// The app in front, for the log line only. The capture is fresh here:
  /// the stored target may still be the app of the last dictation.
  Future<String?> _frontApp() async {
    final controller = ref.read(desktopPasteControllerProvider);
    if (controller == null) return null;
    try {
      await controller.capturePasteTarget().timeout(const Duration(seconds: 1));
      return await controller.getTargetBundleId().timeout(
        const Duration(seconds: 1),
      );
    } on Object {
      return null;
    }
  }
}

final learnCorrectionHotkeyServiceProvider =
    Provider<LearnCorrectionHotkeyService>(LearnCorrectionHotkeyService.new);
