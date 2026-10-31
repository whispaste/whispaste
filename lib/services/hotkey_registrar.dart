import 'dart:async';

import 'package:hotkey_manager/hotkey_manager.dart';

import '../core/logging/app_logger.dart';

/// Thin abstraction over the two [hotKeyManager] operations used by
/// the hotkey service. Swap with a [FakeHotKeyRegistrar] in tests.
abstract class HotKeyRegistrar {
  Future<void> register(
    HotKey hotKey, {
    HotKeyHandler? keyDownHandler,
    HotKeyHandler? keyUpHandler,
  });

  Future<void> unregister(HotKey hotKey);

  /// Whether this registrar supports key-up events.
  ///
  /// macOS: true (hotkey_manager native layer fires onKeyUp).
  /// Windows/Linux: false (RegisterHotKey is key-down only; WH_KEYBOARD_LL
  /// not yet implemented).
  bool get supportsKeyUp;
}

/// A [HotKeyRegistrar] whose registrations can be taken off the system for a
/// while and put back exactly as they were.
///
/// A system-wide registration (macOS Carbon hotkey, Windows RegisterHotKey,
/// Linux X11 grab) takes the key press before the app sees it. While the user
/// records a hotkey, the recorder therefore never saw a combination that is
/// already registered, its own included: pressing the saved Cmd+Ä again left
/// only the modifier in the recorder. [suspend] unregisters every active
/// registration at the system; [resume] registers them again with their
/// handlers. Calls made while suspended only update the remembered set, so
/// [resume] puts back what is current then, not what was current at
/// [suspend].
///
/// Every operation runs in one chain, so a suspend never interleaves with a
/// register or unregister. The chain waits for each operation at most
/// [stepTimeout], so a system call that never answers cannot block it.
class SuspendableHotKeyRegistrar implements HotKeyRegistrar {
  SuspendableHotKeyRegistrar(
    this._inner, {
    this.stepTimeout = const Duration(seconds: 5),
  });

  static final _log = AppLogger('SuspendableHotKeyRegistrar');

  final HotKeyRegistrar _inner;

  /// Upper bound for one system call made by [suspend] or [resume].
  final Duration stepTimeout;

  /// Registrations the app wants, by [HotKey.identifier], in register order.
  final Map<String, _Registration> _wanted = {};

  bool _suspended = false;
  Future<void> _tail = Future<void>.value();

  /// Timers bounding calls in flight; [dispose] cancels them.
  final Set<Timer> _stepTimers = {};
  bool _disposed = false;

  /// True between [suspend] and [resume].
  bool get suspended => _suspended;

  @override
  bool get supportsKeyUp => _inner.supportsKeyUp;

  @override
  Future<void> register(
    HotKey hotKey, {
    HotKeyHandler? keyDownHandler,
    HotKeyHandler? keyUpHandler,
  }) => _serialize(() async {
    // A failed system registration throws to the caller and is not
    // remembered, as without this wrapper.
    if (!_suspended) {
      await _inner.register(
        hotKey,
        keyDownHandler: keyDownHandler,
        keyUpHandler: keyUpHandler,
      );
    }
    _wanted[hotKey.identifier] = _Registration(
      hotKey,
      keyDownHandler,
      keyUpHandler,
    );
  });

  @override
  Future<void> unregister(HotKey hotKey) => _serialize(() async {
    _wanted.remove(hotKey.identifier);
    if (!_suspended) await _inner.unregister(hotKey);
  });

  /// Takes every active registration off the system. Idempotent.
  Future<void> suspend() => _serialize(() async {
    if (_suspended) return;
    _suspended = true;
    for (final r in _wanted.values) {
      await _bounded(_inner.unregister(r.hotKey), 'unregister');
    }
    _log.info(
      'Hotkeys suspended while a hotkey is recorded (${_wanted.length})',
    );
  });

  /// Registers every remembered registration again. Idempotent. Returns the
  /// hotkeys the system refused; they are forgotten, as a failed [register]
  /// would be, so the caller can report and heal them.
  Future<List<HotKey>> resume() {
    final failed = <HotKey>[];
    return _serialize(() async {
      if (!_suspended) return;
      _suspended = false;
      for (final entry in _wanted.entries.toList()) {
        final r = entry.value;
        final ok = await _bounded(
          _inner.register(
            r.hotKey,
            keyDownHandler: r.keyDown,
            keyUpHandler: r.keyUp,
          ),
          'register',
        );
        if (!ok) {
          _wanted.remove(entry.key);
          failed.add(r.hotKey);
        }
      }
      _log.info(
        'Hotkeys restored after recording '
        '(${_wanted.length} ok, ${failed.length} refused)',
      );
    }).then((_) => failed);
  }

  Future<bool> _bounded(Future<void> call, String what) async {
    try {
      await _withinStep(call);
      return true;
    } on TimeoutException {
      _log.warning('Hotkey $what did not answer within $stepTimeout');
      return false;
    } on Object catch (e) {
      _log.warning('Hotkey $what failed: $e');
      return false;
    }
  }

  /// The next operation waits for this one at most [stepTimeout]: a call
  /// that never answers is the caller's to report (the hotkey service bounds
  /// its own steps), it must not hold up every later change.
  Future<void> _serialize(Future<void> Function() action) {
    final run = _tail.then((_) => action());
    _tail = _withinStep(run).then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  /// [call], failing with a [TimeoutException] once [stepTimeout] passes.
  /// Unlike [Future.timeout] the timer is tracked, so [dispose] can cancel
  /// it while a system call still has not answered.
  Future<void> _withinStep(Future<void> call) {
    if (_disposed) return call;
    final done = Completer<void>();
    late final Timer timer;
    timer = Timer(stepTimeout, () {
      _stepTimers.remove(timer);
      if (!done.isCompleted) {
        done.completeError(TimeoutException(null, stepTimeout));
      }
    });
    _stepTimers.add(timer);
    call
        .then<void>(
          (_) {
            if (!done.isCompleted) done.complete();
          },
          onError: (Object e, StackTrace s) {
            if (!done.isCompleted) done.completeError(e, s);
          },
        )
        .whenComplete(() {
          timer.cancel();
          _stepTimers.remove(timer);
        });
    return done.future;
  }

  /// Cancels the timers bounding calls in flight. Later calls still reach
  /// the system, so the owner can release its hotkeys, but are no longer
  /// bounded: nothing is waiting for them once the owner is gone.
  void dispose() {
    _disposed = true;
    for (final timer in _stepTimers) {
      timer.cancel();
    }
    _stepTimers.clear();
  }
}

class _Registration {
  const _Registration(this.hotKey, this.keyDown, this.keyUp);

  final HotKey hotKey;
  final HotKeyHandler? keyDown;
  final HotKeyHandler? keyUp;
}
