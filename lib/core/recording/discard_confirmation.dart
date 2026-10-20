/// Confirm-before-discard for long recordings (9.10 follow-up).
///
/// A cancel press during a recording that is already [longRecordingThreshold]
/// long does not discard at once: it arms a confirmation for
/// [confirmWindow]. A second cancel press inside that window discards. Short
/// recordings are discarded immediately, as before.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Recordings at least this long ask before they are discarded.
const longRecordingThreshold = Duration(seconds: 30);

/// How long the armed confirmation waits for the second cancel press.
const confirmWindow = Duration(seconds: 4);

class DiscardConfirmNotifier extends Notifier<bool> {
  Timer? _disarmTimer;

  @override
  bool build() {
    ref.onDispose(() => _disarmTimer?.cancel());
    return false;
  }

  /// Handles a cancel press. Returns true when the recording should be
  /// discarded now, false when the press only armed the confirmation.
  bool onCancelPressed(Duration elapsed) {
    if (elapsed < longRecordingThreshold || state) {
      disarm();
      return true;
    }
    state = true;
    _disarmTimer?.cancel();
    _disarmTimer = Timer(confirmWindow, disarm);
    return false;
  }

  void disarm() {
    _disarmTimer?.cancel();
    _disarmTimer = null;
    state = false;
  }
}

/// Whether a discard confirmation is currently armed.
final discardConfirmProvider = NotifierProvider<DiscardConfirmNotifier, bool>(
  DiscardConfirmNotifier.new,
);
