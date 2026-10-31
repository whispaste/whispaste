/// In-window [Paster] for the onboarding practice chat (Onboarding v6, V06).
library;

import 'package:flutter/services.dart';

import '../../core/logging/app_logger.dart';
import '../../services/paste/paster.dart';

final _log = AppLogger('PracticeChatPaster');

/// Delivers a dictation into the practice field of the onboarding window.
///
/// The native paste cannot target WhisPaste's own window: macOS and Windows
/// refuse their own frontmost window as a paste target. The practice step
/// therefore inserts through this paster, and the orchestrator runs its usual
/// paste outcome handling on top of it (see `_deliverToSandbox`).
///
/// [insert] appends the text to the field and returns whether the field took
/// it. When it did not, the text goes to the clipboard, which is what the
/// chat promises in that case, and the outcome is [PasteOutcome.failed].
class PracticeChatPaster implements Paster {
  PracticeChatPaster({required this.insert});

  /// Appends [text] to the practice field; `false` when the field is gone.
  final bool Function(String text) insert;

  @override
  Future<void> prime() async {}

  @override
  Future<PasteOutcome> paste(String text, PasteOptions options) async {
    if (insert(text)) return PasteOutcome.success;
    try {
      await Clipboard.setData(ClipboardData(text: text));
    } on Exception catch (e) {
      // The chat still says the text is on the clipboard; a refused write is
      // the one case where that claim is false, and nothing else can fix it.
      _log.warning('Copying the practice dictation to the clipboard failed', e);
    }
    return PasteOutcome.failed;
  }

  /// The practice field takes text only as a whole paste, never as keystrokes.
  @override
  Future<PasteOutcome> typeText(String text, PasteOptions options) async =>
      PasteOutcome.platformUnavailable;

  @override
  Future<PasteCapability> checkCapability({
    bool promptIfMissing = false,
  }) async => const PasteCapability(status: PasteCapabilityStatus.ready);

  @override
  Future<String?> getTargetBundleId() async => null;
}
