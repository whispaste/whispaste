/// Announces a dictation whose Smart-Mode result was saved and can be undone
/// (Block C). The app shell turns each new notice into the "Rückgängig" toast.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

@immutable
class SmartModeUndoNotice {
  const SmartModeUndoNotice({required this.entryId, required this.serial});

  final String entryId;

  /// Makes two notices for the same entry distinct for listeners.
  final int serial;
}

class SmartModeUndoNoticeNotifier extends Notifier<SmartModeUndoNotice?> {
  @override
  SmartModeUndoNotice? build() => null;

  void announce(String entryId) {
    state = SmartModeUndoNotice(
      entryId: entryId,
      serial: (state?.serial ?? 0) + 1,
    );
  }
}

final smartModeUndoNoticeProvider =
    NotifierProvider<SmartModeUndoNoticeNotifier, SmartModeUndoNotice?>(
      SmartModeUndoNoticeNotifier.new,
    );
