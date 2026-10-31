/// Undo for a selection edit that changed names (2c, DEV-165). The name toast
/// offers it; the edit itself has no history entry to reverse.
library;

import 'package:flutter/foundation.dart';

import '../paste/paster.dart';

/// What a selection edit left behind: the text it replaced, the app that
/// received the insert and the paste it went through.
@immutable
class SelectionUndoTicket {
  const SelectionUndoTicket({
    required this.originalText,
    required this.targetBundleId,
    required this.insertSerial,
    required this.sinceInsert,
  });

  final String originalText;

  /// Frontmost app right after the insert. Null when the platform cannot say.
  final String? targetBundleId;

  /// [UndoKeystrokeSender.cleanPasteSerial] right after the insert. Null when
  /// the insert was typed (Unicode fallback) or the platform has no clean
  /// paste, which rules out the keystroke undo.
  final int? insertSerial;

  /// Started before the paste call, so anything typed during the paste counts
  /// as "since the insert" (conservative).
  final Stopwatch sinceInsert;
}

/// Serial of the last clean insert on [paster] (see [SelectionUndoTicket]).
int? cleanInsertSerial(Paster paster) {
  if (paster case final UndoKeystrokeSender sender) {
    return sender.cleanPasteSerial;
  }
  return null;
}

enum SelectionUndoOutcome {
  /// Cmd+Z / Ctrl+Z went to the target app, which reverted its own edit.
  keystrokeSent,

  /// The original text is on the clipboard; the user pastes it (the toast
  /// says so and that the previous clipboard content was replaced).
  copiedToClipboard,

  /// Neither path worked; the edit stays as it is.
  failed,
}

/// Reverts a selection edit.
///
/// The keystroke is sent only when all of these hold: the insert was a clean
/// native paste, no other insert or recording start happened since (the
/// serial is still the ticket's), the frontmost app is the one that received
/// the insert, and no hardware key went down since the insert. Every other
/// case, and a keystroke that fails to send, copies the original text to the
/// clipboard through the transient write. Windows and Linux have no undo
/// keystroke yet, so they always take the clipboard path.
Future<SelectionUndoOutcome> undoSelectionEdit({
  required SelectionUndoTicket ticket,
  required Paster paster,
}) async {
  if (paster case final UndoKeystrokeSender sender) {
    if (await _keystrokeAllowed(ticket, paster, sender) &&
        await sender.sendUndoShortcut()) {
      return SelectionUndoOutcome.keystrokeSent;
    }
    final copied = await sender.copyOriginalToClipboard(ticket.originalText);
    return copied
        ? SelectionUndoOutcome.copiedToClipboard
        : SelectionUndoOutcome.failed;
  }
  return SelectionUndoOutcome.failed;
}

Future<bool> _keystrokeAllowed(
  SelectionUndoTicket ticket,
  Paster paster,
  UndoKeystrokeSender sender,
) async {
  final serial = ticket.insertSerial;
  if (serial == null || sender.cleanPasteSerial != serial) return false;
  final frontmost = await paster.getTargetBundleId();
  if (frontmost == null || frontmost != ticket.targetBundleId) return false;
  final snapshot = await sender.inputIdleSnapshot();
  return !userInputSince(ticket.sinceInsert.elapsed, snapshot);
}
