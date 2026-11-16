import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../logging/app_logger.dart';

final _log = AppLogger('PolledChannelCall');

/// Outcome of one [PolledChannelCall.run].
enum PolledCallStatus {
  /// The native side answered within the deadline.
  answered,

  /// No answer within the deadline. The native call may still be pending.
  timedOut,

  /// Not sent: an earlier call is still running, or an earlier call never
  /// answered. Nothing new was put on the channel.
  skipped,
}

class PolledCallResult<T> {
  const PolledCallResult._(this.status, this.value);

  final PolledCallStatus status;

  /// Set only when [status] is [PolledCallStatus.answered].
  final T? value;
}

/// Deadline plus single-flight for a platform call that is polled on a timer.
///
/// Why this exists: a native reply that never arrives leaves the Dart future
/// pending and its handle open. A poller that fires again on every tick would
/// then stack one unanswered handle per tick. This wrapper keeps the poller
/// from doing that:
///
/// * A polled call is sent only while no earlier call is outstanding
///   ([PolledCallStatus.skipped] otherwise). That covers a call still in
///   flight and one that missed its deadline and has not answered yet, so an
///   unresponsive channel adds no new handles.
/// * A call that misses [timeout] is reported as [PolledCallStatus.timedOut],
///   so the caller can keep its last known state instead of hanging.
/// * A call with `force: true` (a user-triggered prompt) is sent even while
///   another call is outstanding, but never after [dispose]. It gets its own
///   deadline.
///
/// The timeout is measured on the Dart side; it does not cancel the native
/// call. [unansweredCalls] reports how many sent calls have not answered yet.
class PolledChannelCall<T> {
  PolledChannelCall({
    required this.timeout,
    this.staleWarnAfter = const Duration(minutes: 5),
  });

  final Duration timeout;

  /// A sent call still unanswered after this long gets one warning in the
  /// log (never repeated for the same call), so a permanently silent native
  /// side is visible without a log line per poll tick.
  final Duration staleWarnAfter;

  int _staleWarnings = 0;

  /// Number of stale-call warnings written so far.
  @visibleForTesting
  int get staleWarnings => _staleWarnings;

  int _unanswered = 0;
  bool _disposed = false;

  /// Deadline timers of the calls whose caller still waits, so [dispose] can
  /// cancel them and release those callers.
  final _waiting = <Completer<PolledCallResult<T>>, Timer>{};

  /// Stale-warning timers of the sent calls that have not answered yet, so
  /// [dispose] can cancel them too.
  final _staleTimers = <Timer>{};

  /// Sent calls that have not completed yet, including timed-out ones.
  int get unansweredCalls => _unanswered;

  /// Runs [send] under the deadline. Errors thrown by [send] propagate to the
  /// caller unchanged, unless the deadline already ended the call (then the
  /// caller has its [PolledCallStatus.timedOut] result).
  ///
  /// The deadline is an explicit [Timer] (not [Future.timeout]) so that
  /// [dispose] can cancel it. A pending deadline timer would otherwise outlive
  /// the owner of this call.
  Future<PolledCallResult<T>> run(
    Future<T> Function() send, {
    bool force = false,
  }) {
    if (_disposed || (_unanswered > 0 && !force)) {
      return Future.value(
        const PolledCallResult._(PolledCallStatus.skipped, null),
      );
    }
    final Future<T> pending;
    try {
      pending = send();
    } on Object catch (error, stack) {
      return Future.error(error, stack);
    }
    _unanswered++;
    // Counts the call as answered when it completes, even after a timeout
    // and even when it fails. The error is delivered to the caller below.
    final settled = pending.then<void>((_) {}, onError: (Object _) {});
    late final Timer staleTimer;
    staleTimer = Timer(staleWarnAfter, () {
      _staleTimers.remove(staleTimer);
      _staleWarnings++;
      _log.warning(
        'Native call unanswered for ${staleWarnAfter.inSeconds}s; '
        'further polls are skipped until it answers',
      );
    });
    _staleTimers.add(staleTimer);
    unawaited(
      settled.whenComplete(() {
        _unanswered--;
        _staleTimers.remove(staleTimer);
        staleTimer.cancel();
      }),
    );

    final done = Completer<PolledCallResult<T>>();
    _waiting[done] = Timer(timeout, () {
      _waiting.remove(done);
      if (!done.isCompleted) {
        done.complete(
          const PolledCallResult._(PolledCallStatus.timedOut, null),
        );
      }
    });
    pending.then<void>(
      (value) {
        _waiting.remove(done)?.cancel();
        if (!done.isCompleted) {
          done.complete(PolledCallResult._(PolledCallStatus.answered, value));
        }
      },
      onError: (Object error, StackTrace stack) {
        _waiting.remove(done)?.cancel();
        if (done.isCompleted) {
          // The caller already got its timeout; the error has no receiver.
          _log.debug('Native call failed after its deadline', error);
        } else {
          done.completeError(error, stack);
        }
      },
    );
    return done.future;
  }

  /// Cancels every deadline and stale-warning timer and releases the callers
  /// that wait for them. Call from the owner's dispose hook. Later [run] calls
  /// are skipped.
  void dispose() {
    _disposed = true;
    for (final timer in _staleTimers) {
      timer.cancel();
    }
    _staleTimers.clear();
    final waiting = Map.of(_waiting);
    _waiting.clear();
    waiting.forEach((done, deadline) {
      deadline.cancel();
      if (!done.isCompleted) {
        done.complete(
          const PolledCallResult._(PolledCallStatus.timedOut, null),
        );
      }
    });
  }
}
