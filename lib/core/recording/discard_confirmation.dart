/// Confirm-before-discard for long recordings (9.10 follow-up).
///
/// A cancel press during a recording that is already [longRecordingThreshold]
/// long does not discard at once: it arms a confirmation for
/// [confirmWindow]. A second cancel press inside that window discards. Short
/// recordings are discarded immediately, as before.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'recording_state.dart' show RecordingPhase;

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
  ///
  /// [alwaysAsk]: a card is open over the recording. The card offers other
  /// ways out, so a stray Esc must not throw the dictation away: it asks
  /// first, however short the recording is.
  bool onCancelPressed(Duration elapsed, {bool alwaysAsk = false}) {
    if ((elapsed < longRecordingThreshold && !alwaysAsk) || state) {
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

/// One rule for every cancel surface (Escape, overlay X, overlay context
/// menu "Cancel"): outside an active recording a cancel discards at once,
/// during a recording it goes through [DiscardConfirmNotifier.onCancelPressed].
/// Returns true when the caller should discard now.
bool cancelPressDiscardsNow(
  RecordingPhase phase,
  Duration elapsed,
  DiscardConfirmNotifier confirm, {
  bool cardOpen = false,
}) =>
    phase != RecordingPhase.recording ||
    confirm.onCancelPressed(elapsed, alwaysAsk: cardOpen);

/// Whether a notice card is open over the running recording. Written by the
/// overlay service, read by the cancel key, so Esc asks before it discards.
class RecordingCardOpenNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool open) {
    if (state != open) state = open;
  }
}

final recordingCardOpenProvider =
    NotifierProvider<RecordingCardOpenNotifier, bool>(
      RecordingCardOpenNotifier.new,
    );

/// Whether a discard confirmation is currently armed.
final discardConfirmProvider = NotifierProvider<DiscardConfirmNotifier, bool>(
  DiscardConfirmNotifier.new,
);
