import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/settings_provider.dart';
import '../../core/data/database.dart';
import '../../core/logging/app_logger.dart';
import '../../core/recording/recording_state.dart';
import 'paster.dart';

final _log = AppLogger('Repaste');

/// The text of the last dictation in this session, kept in memory only. It
/// lets the "paste the last dictation again" hotkey work with saving off;
/// the orchestrator sets it whenever it pastes a dictation.
class LastDictationText extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String text) => state = text;
}

/// Counts the presses of the repaste hotkey that found nothing to paste. The
/// overlay listens and shows a short notice, so a press is never silent.
class RepasteEmptyNotice extends Notifier<int> {
  @override
  int build() => 0;

  void raise() => state++;
}

final repasteEmptyNoticeProvider = NotifierProvider<RepasteEmptyNotice, int>(
  RepasteEmptyNotice.new,
);

final lastDictationTextProvider = NotifierProvider<LastDictationText, String?>(
  LastDictationText.new,
);

/// Pastes the last dictation again into the app in front, through the same
/// paster and paste options as a dictation. The text of this session comes
/// first; after a restart the newest saved recording. Never runs during a
/// recording, so the hotkey path of a dictation stays untouched.
class RepasteService {
  RepasteService(this.ref);

  final Ref ref;

  Future<PasteOutcome?> pasteLast() async {
    if (ref.read(recordingPhaseProvider) != RecordingPhase.idle) {
      _log.info('Repaste ignored: a recording is running');
      return null;
    }
    final text =
        ref.read(lastDictationTextProvider) ??
        await ref.read(historyDatabaseProvider).latestEntryText();
    if (text == null || text.trim().isEmpty) {
      _log.info('Repaste: nothing dictated yet');
      ref.read(repasteEmptyNoticeProvider.notifier).raise();
      return null;
    }
    final paster = ref.read(pasterProvider);
    if (paster == null) return PasteOutcome.platformUnavailable;
    final settings = ref.read(settingsProvider).value ?? AppSettings.defaults;
    final behavior = settings.behavior;
    await paster.prime();
    final outcome = await paster.paste(
      text,
      PasteOptions(
        autoPasteDelayMs: behavior.autoPasteDelay,
        blocklist: behavior.autoPasteBlocklist,
        copyBlockedToClipboard:
            behavior.copyBlockedToClipboard || !settings.history.saveHistory,
        restoreClipboardAfterPaste: behavior.restoreClipboardAfterPaste,
        restoreClipboardWithoutReceipt: behavior.restoreClipboardWithoutReceipt,
      ),
    );
    if (outcome != PasteOutcome.success) {
      _log.warning('Repaste failed: $outcome');
    }
    return outcome;
  }
}

final repasteServiceProvider = Provider<RepasteService>(RepasteService.new);
