/// Deadline of one local decode that progress can push out (#1639).
///
/// Starts at the local budget ([localTranscriptionBudget]). Each progress
/// report that moves forward sets the deadline to at least "now + stall
/// window", never past the hard cap. A decode that keeps reporting progress
/// therefore finishes even on a machine slower than its budget assumed; one
/// that stops moving runs out after the stall window.
library;

import 'dart:async';

import 'package:clock/clock.dart';

class TranscriptionDeadline {
  TranscriptionDeadline({
    required Duration initial,
    required this.stallWindow,
    required Duration hardCap,
  }) : _start = clock.now() {
    _hardCapAt = _start.add(hardCap);
    final first = _start.add(initial);
    _deadline = first.isAfter(_hardCapAt) ? _hardCapAt : first;
  }

  final Duration stallWindow;
  final DateTime _start;
  late final DateTime _hardCapAt;
  late DateTime _deadline;
  double _lastFraction = -1;
  Timer? _timer;
  Completer<void>? _expired;

  /// Time from the start to the current deadline.
  Duration get current => _deadline.difference(_start);

  /// Feeds one progress fraction (`0..1`). Only a fraction above the last one
  /// extends the deadline.
  void reportProgress(double fraction) {
    if (!(fraction > _lastFraction)) return;
    _lastFraction = fraction;
    var next = clock.now().add(stallWindow);
    if (next.isAfter(_hardCapAt)) next = _hardCapAt;
    if (!next.isAfter(_deadline)) return;
    _deadline = next;
    if (_expired != null) _arm();
  }

  /// Completes like [work], or throws [TimeoutException] once the deadline
  /// passes first. [work] keeps running after a timeout; a late error of it
  /// is swallowed here (the caller owns the native call).
  Future<T> guard<T>(Future<T> work) {
    // Synchronous: the caller resumes in the same microtask as a plain
    // `await work` would. A failing GPU decode must reach its recovery code
    // before a waiting dictation passes the decode gate (#404).
    final result = Completer<T>.sync();
    final expired = _expired = Completer<void>();
    _arm();
    work.then(
      (value) {
        _timer?.cancel();
        if (!result.isCompleted) result.complete(value);
      },
      onError: (Object e, StackTrace st) {
        _timer?.cancel();
        if (!result.isCompleted) result.completeError(e, st);
      },
    );
    expired.future.then((_) {
      if (!result.isCompleted) {
        result.completeError(
          TimeoutException('local transcription budget exceeded', current),
        );
      }
    });
    return result.future;
  }

  void _arm() {
    _timer?.cancel();
    final wait = _deadline.difference(clock.now());
    _timer = Timer(wait.isNegative ? Duration.zero : wait, () {
      final expired = _expired;
      if (expired != null && !expired.isCompleted) expired.complete();
    });
  }
}
