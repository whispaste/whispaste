/// One chain of hotkey operations (register, unregister, start or stop a
/// watch): every step runs alone, after the previous one has ended.
///
/// A step that has not ended after [limit] is aborted: its caller gets the
/// limit result at once, and [ChainStep.aborted] tells the step to stop
/// before its next native call. The chain still waits for the aborted step
/// to end, so the next step never runs beside it on the same registrations.
/// Only when the aborted step has not ended after a further [limit] (a
/// native call that never answers) does the chain move on, so one hung call
/// cannot block every later change for good (#293, F33-4).
///
/// [close] ends the chain at quit: every waiting caller gets its abort
/// result, no future stays open (F33-5).
library;

import 'dart:async';

/// What a running step can ask the chain.
class ChainStep {
  bool _aborted = false;

  /// True once the step ran past the limit or the chain was closed. An
  /// aborted step does no further native work and writes no status.
  bool get aborted => _aborted;
}

class HotkeyChain {
  HotkeyChain({required this.limit, this.onStuck});

  /// Longest time one step may hold the chain before it is aborted.
  final Duration limit;

  /// Told when an aborted step still has not ended after the backstop, or
  /// fails after its caller was already answered.
  final void Function(String message)? onStuck;

  Future<void> _tail = Future<void>.value();
  final Set<void Function()> _closers = {};
  bool _closed = false;

  /// Runs [action] after every earlier step has ended. Completes with its
  /// result, with [onLimit]'s once [limit] passes, or with [aborted] when the
  /// chain is closed first.
  Future<T> run<T>(
    Future<T> Function(ChainStep step) action, {
    required T Function() onLimit,
    required T aborted,
  }) {
    final result = Completer<T>();
    final step = ChainStep();
    final timers = <Timer>{};
    void finish(T value) {
      if (!result.isCompleted) result.complete(value);
    }

    void close() {
      step._aborted = true;
      for (final t in timers) {
        t.cancel();
      }
      finish(aborted);
    }

    if (_closed) {
      step._aborted = true;
      return Future<T>.value(aborted);
    }
    _closers.add(close);

    _tail = _tail.then((_) async {
      if (_closed || step.aborted) return;
      final ended = Completer<void>();
      timers.add(
        Timer(limit, () {
          step._aborted = true;
          // Backstop, armed before [onLimit] runs so a throwing callback
          // cannot skip it: the aborted step does nothing more, but a native
          // call that never answers must not hold the chain for good.
          timers.add(
            Timer(limit, () {
              if (ended.isCompleted) return;
              onStuck?.call(
                'Aborted hotkey step still has not ended after '
                '${limit.inSeconds * 2} s; the next step runs',
              );
              ended.complete();
            }),
          );
          if (!result.isCompleted) result.complete(onLimit());
        }),
      );
      unawaited(
        Future<T>.sync(() => action(step)).then(
          (value) {
            finish(value);
            if (!ended.isCompleted) ended.complete();
          },
          onError: (Object e, StackTrace st) {
            if (result.isCompleted) {
              onStuck?.call('Aborted hotkey step failed late: $e');
            } else {
              result.completeError(e, st);
            }
            if (!ended.isCompleted) ended.complete();
          },
        ),
      );
      await ended.future;
      for (final t in timers) {
        t.cancel();
      }
      _closers.remove(close);
    });
    return result.future;
  }

  /// Aborts every running and waiting step and completes their callers.
  /// Steps queued afterwards return their abort result at once.
  void close() {
    _closed = true;
    for (final close in _closers.toList()) {
      close();
    }
    _closers.clear();
  }
}
