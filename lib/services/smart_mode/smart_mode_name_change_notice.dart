/// Announces that a selection edit changed names (2c, DEV-165). The app shell
/// turns each notice into the non-blocking name toast with its undo. Holds
/// counts only: the toast never shows the names themselves.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../selection_edit/selection_undo.dart';

@immutable
class SmartModeNameChangeNotice {
  const SmartModeNameChangeNotice({
    required this.count,
    required this.ticket,
    required this.serial,
  });

  /// Number of changed names (the larger side of the diff).
  final int count;

  final SelectionUndoTicket ticket;

  /// Makes two notices distinct for listeners.
  final int serial;
}

class SmartModeNameChangeNoticeNotifier
    extends Notifier<SmartModeNameChangeNotice?> {
  @override
  SmartModeNameChangeNotice? build() => null;

  void announce({required int count, required SelectionUndoTicket ticket}) {
    state = SmartModeNameChangeNotice(
      count: count,
      ticket: ticket,
      serial: (state?.serial ?? 0) + 1,
    );
  }

  /// Drops the offer, e.g. once it was used or another dictation started.
  void clear() {
    state = null;
  }

  /// Drops the offer only if it is still [serial]; a toast that expires after
  /// a newer notice was announced must not remove that one.
  void clearIfSerial(int serial) {
    if (state?.serial == serial) state = null;
  }
}

final smartModeNameChangeNoticeProvider =
    NotifierProvider<
      SmartModeNameChangeNoticeNotifier,
      SmartModeNameChangeNotice?
    >(SmartModeNameChangeNoticeNotifier.new);
