import 'dart:async';

import 'package:hotkey_manager/hotkey_manager.dart';

import '../core/logging/app_logger.dart';
import 'hotkey_event_time.dart';

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
  /// Windows/Linux: false (their registration APIs deliver key-down only;
  /// the separate monitor supplies releases for the main dictation hotkey).
  bool get supportsKeyUp;
}

/// Registrars that suppress held-key repeats before delivering key-downs.
/// This is independent of whether they can deliver key-up events.
abstract interface class RepeatFilteringHotKeyRegistrar {
  bool get filtersKeyRepeat;
}

extension HotKeyRepeatSupport on HotKeyRegistrar {
  bool get filtersKeyRepeat => switch (this) {
    final RepeatFilteringHotKeyRegistrar registrar =>
      registrar.filtersKeyRepeat,
    _ => false,
  };
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
/// Every operation runs in one chain and holds it until it ends, so a suspend
/// never interleaves with a register or unregister. Each system call is
/// bounded by [stepTimeout]: a single [register] or [unregister] then fails
/// with a [TimeoutException], and a registration that answers only after its
/// timeout is taken off the system again unless it is wanted by then. Only a
/// registration that answered in time is remembered, so a late answer can
/// never bring back a hotkey the caller has given up (core review L-15 F15-2).
class SuspendableHotKeyRegistrar
    implements
        HotKeyRegistrar,
        RepeatFilteringHotKeyRegistrar,
        HotKeyEventTimeSource {
  SuspendableHotKeyRegistrar(
    this._inner, {
    this.stepTimeout = const Duration(seconds: 5),
  });

  static final _log = AppLogger('SuspendableHotKeyRegistrar');

  final HotKeyRegistrar _inner;

  /// Upper bound for one system call, and for how long a single register or
  /// unregister holds the chain.
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
  bool get filtersKeyRepeat => _inner.filtersKeyRepeat;

  @override
  Duration? get lastEventAt => switch (_inner) {
    final HotKeyEventTimeSource source => source.lastEventAt,
    _ => null,
  };

  @override
  Future<void> register(
    HotKey hotKey, {
    HotKeyHandler? keyDownHandler,
    HotKeyHandler? keyUpHandler,
  }) => _serialize(() async {
    // A failed or timed-out system registration throws to the caller and is
    // not remembered, as without this wrapper.
    if (!_suspended) {
      final call = _inner.register(
        hotKey,
        keyDownHandler: keyDownHandler,
        keyUpHandler: keyUpHandler,
      );
      try {
        await _withinStep(call);
      } on TimeoutException {
        _log.warning('Hotkey register did not answer within $stepTimeout');
        _dropIfLate(call, hotKey);
        rethrow;
      }
    }
    _wanted[hotKey.identifier] = _Registration(
      hotKey,
      keyDownHandler,
      keyUpHandler,
    );
  });

  @override
  Future<void> unregister(HotKey hotKey) => _serialize(() async {
    // Only what this registrar put on the system is taken off again: the
    // Windows plugin looks the identifier up with a throwing `at()` and a
    // C++ exception in the channel handler can end the app (#541).
    final known = _wanted.remove(hotKey.identifier) != null;
    if (known && !_suspended) await _withinStep(_inner.unregister(hotKey));
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
        final call = _inner.register(
          r.hotKey,
          keyDownHandler: r.keyDown,
          keyUpHandler: r.keyUp,
        );
        final ok = await _bounded(call, 'register');
        if (!ok) {
          _dropIfLate(call, r.hotKey);
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

  /// A register [call] that timed out counts as refused, but the system may
  /// still accept it later. Such a registration would stay on the system
  /// with no unregister ever reaching it, so it is taken off again, in the
  /// chain, unless the hotkey is wanted and active by then.
  void _dropIfLate(Future<void> call, HotKey hotKey) {
    unawaited(
      call.then<void>((_) {
        if (_disposed) return;
        _log.warning('Hotkey register answered after its timeout; undone');
        unawaited(
          _serialize(() async {
            if (!_suspended && _wanted.containsKey(hotKey.identifier)) return;
            await _bounded(_inner.unregister(hotKey), 'late unregister');
          }),
        );
      }, onError: (Object _) {}),
    );
  }

  /// The next operation starts once this one has finished. Every system call
  /// inside is bounded, so the chain is too; a timer around a whole operation
  /// released it while a slow suspend still ran, and the following resume
  /// registered what that suspend then removed (core review L-14 F2).
  Future<void> _serialize(Future<void> Function() action) {
    final run = _tail.then((_) => action());
    _tail = run.then<void>((_) {}, onError: (Object _) {});
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
