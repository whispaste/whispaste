import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:whispaste/services/hotkey_self_heal.dart';
import 'package:whispaste/services/hotkey_registrar.dart';

/// Records what is registered at the "system" right now.
class _SystemRegistrar implements HotKeyRegistrar {
  final Map<String, HotKeyHandler?> active = {};
  final Set<String> refuse = {};
  bool hangUnregister = false;

  /// Simulated time each system call takes; zero answers at once.
  Duration delay = Duration.zero;

  /// Overrides [delay] for register calls only, when set.
  Duration? registerDelay;

  /// Every call in the order the system received it, e.g. `register:A`.
  final List<String> calls = [];

  @override
  bool get supportsKeyUp => false;

  @override
  Future<void> register(
    HotKey hotKey, {
    HotKeyHandler? keyDownHandler,
    HotKeyHandler? keyUpHandler,
  }) async {
    calls.add('register:${hotKey.identifier}');
    final wait = registerDelay ?? delay;
    if (wait > Duration.zero) await Future<void>.delayed(wait);
    if (refuse.contains(hotKey.identifier)) {
      throw PlatformException(code: 'hotkey_unavailable');
    }
    active[hotKey.identifier] = keyDownHandler;
  }

  @override
  Future<void> unregister(HotKey hotKey) async {
    calls.add('unregister:${hotKey.identifier}');
    if (hangUnregister) return Completer<void>().future;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    active.remove(hotKey.identifier);
  }
}

HotKey _key(LogicalKeyboardKey key) =>
    HotKey(key: key, modifiers: const [HotKeyModifier.meta]);

void main() {
  late _SystemRegistrar system;
  late SuspendableHotKeyRegistrar registrar;

  setUp(() {
    system = _SystemRegistrar();
    registrar = SuspendableHotKeyRegistrar(system);
  });

  test(
    'unregistering a hotkey the system never had does not reach it',
    () async {
      final a = _key(LogicalKeyboardKey.keyA);
      final refused = _key(LogicalKeyboardKey.keyB);
      system.refuse.add(refused.identifier);
      await registrar.register(a);
      await expectLater(registrar.register(refused), throwsA(anything));

      await registrar.unregister(refused);
      await registrar.unregister(_key(LogicalKeyboardKey.keyC));
      await registrar.unregister(a);
      await registrar.unregister(a);

      expect(system.calls.where((c) => c.startsWith('unregister')), [
        'unregister:${a.identifier}',
      ]);
    },
  );

  test('suspend takes every registration off the system', () async {
    final a = _key(LogicalKeyboardKey.keyA);
    final b = _key(LogicalKeyboardKey.keyB);
    await registrar.register(a);
    await registrar.register(b);

    await registrar.suspend();

    expect(system.active, isEmpty);
  });

  test(
    'resume after a cancelled recording restores the same handlers',
    () async {
      var pressed = 0;
      final a = _key(LogicalKeyboardKey.keyA);
      await registrar.register(a, keyDownHandler: (_) => pressed++);

      await registrar.suspend();
      final refused = await registrar.resume();

      expect(refused, isEmpty);
      expect(system.active.keys, [a.identifier]);
      system.active[a.identifier]!(a);
      expect(pressed, 1);
    },
  );

  test(
    'a hotkey saved while suspended is the one registered on resume',
    () async {
      final old = _key(LogicalKeyboardKey.keyA);
      final saved = _key(LogicalKeyboardKey.keyB);
      await registrar.register(old);
      await registrar.suspend();

      await registrar.unregister(old);
      await registrar.register(saved);
      expect(system.active, isEmpty, reason: 'nothing reaches the system yet');

      await registrar.resume();
      expect(system.active.keys, [saved.identifier]);
    },
  );

  test(
    'unregistering while suspended does not reach the system again',
    () async {
      // The suspend already took the hotkey off; a second unregister would hit
      // the Windows plugin's throwing lookup (#541).
      final a = _key(LogicalKeyboardKey.keyA);
      await registrar.register(a);
      await registrar.suspend();
      system.calls.clear();

      await registrar.unregister(a);

      expect(system.calls, isEmpty);
      await registrar.resume();
      expect(system.active, isEmpty);
    },
  );

  test(
    'a hotkey the system refuses on resume is reported and forgotten',
    () async {
      final a = _key(LogicalKeyboardKey.keyA);
      await registrar.register(a);
      await registrar.suspend();
      system.refuse.add(a.identifier);

      final refused = await registrar.resume();

      expect(refused.map((h) => h.identifier), [a.identifier]);
      system.refuse.clear();
      await registrar.suspend();
      expect(await registrar.resume(), isEmpty, reason: 'not retried blindly');
    },
  );

  test('suspend and resume are idempotent', () async {
    final a = _key(LogicalKeyboardKey.keyA);
    await registrar.register(a);

    await registrar.suspend();
    await registrar.suspend();
    await registrar.resume();
    await registrar.resume();

    expect(system.active.keys, [a.identifier]);
    expect(registrar.suspended, isFalse);
  });

  test('a system call that never answers does not block the chain', () {
    fakeAsync((async) {
      final bounded = SuspendableHotKeyRegistrar(
        system,
        stepTimeout: const Duration(seconds: 1),
      );
      final a = _key(LogicalKeyboardKey.keyA);
      bounded.register(a);
      async.flushMicrotasks();
      system.hangUnregister = true;

      var resumed = false;
      bounded.suspend();
      bounded.resume().then((_) => resumed = true);
      async.elapse(const Duration(seconds: 2));

      expect(resumed, isTrue);
    });
  });

  test('dispose leaves no timer behind for a call that never answers', () {
    fakeAsync((async) {
      final bounded = SuspendableHotKeyRegistrar(system);
      final a = _key(LogicalKeyboardKey.keyA);
      bounded.register(a);
      async.flushMicrotasks();
      system.hangUnregister = true;
      bounded.unregister(a);
      async.flushMicrotasks();
      expect(async.pendingTimers, isNotEmpty);

      bounded.dispose();

      expect(async.pendingTimers, isEmpty);
    });
  });

  test('a slow suspend finishes before the resume after it starts', () {
    // Core review L-14 F2: three calls of 4 s each outlast one 5 s step.
    fakeAsync((async) {
      final slow = SuspendableHotKeyRegistrar(system);
      final keys = [
        _key(LogicalKeyboardKey.keyA),
        _key(LogicalKeyboardKey.keyB),
        _key(LogicalKeyboardKey.keyC),
      ];
      for (final k in keys) {
        slow.register(k);
      }
      async.flushMicrotasks();
      system.delay = const Duration(seconds: 4);
      system.calls.clear();

      List<HotKey>? refused;
      slow.suspend();
      slow.resume().then((r) => refused = r);
      async.elapse(const Duration(seconds: 30));

      expect(system.calls.take(3), everyElement(startsWith('unregister:')));
      expect(system.calls.skip(3), everyElement(startsWith('register:')));
      expect(refused, isEmpty);
      expect(system.active.keys, keys.map((k) => k.identifier));
      expect(slow.suspended, isFalse);
    });
  });

  test('a resume answered after its timeout is taken off again', () {
    // Core review L-14 F3: the refused hotkey is forgotten, so a late
    // success must not stay on the system without an owner.
    fakeAsync((async) {
      final a = _key(LogicalKeyboardKey.keyA);
      final bounded = SuspendableHotKeyRegistrar(system);
      bounded.register(a);
      bounded.suspend();
      async.flushMicrotasks();
      system.delay = const Duration(seconds: 7);

      List<HotKey>? refused;
      bounded.resume().then((r) => refused = r);
      async.elapse(const Duration(seconds: 6));
      expect(refused?.map((h) => h.identifier), [a.identifier]);

      async.elapse(const Duration(seconds: 20));
      expect(system.active, isEmpty);
      expect(system.calls.last, 'unregister:${a.identifier}');
    });
  });

  test('a register that times out fails and is not remembered', () {
    // Core review L-15 F15-2: the caller gets the timeout, and a later
    // resume does not bring the given-up hotkey back.
    fakeAsync((async) {
      final a = _key(LogicalKeyboardKey.keyA);
      final bounded = SuspendableHotKeyRegistrar(system);
      system.registerDelay = const Duration(seconds: 7);
      Object? error;
      bounded.register(a).catchError((Object e) => error = e);
      async.elapse(const Duration(seconds: 6));
      expect(error, isA<TimeoutException>());

      async.elapse(const Duration(seconds: 5));
      system.registerDelay = null;
      system.calls.clear();
      bounded.suspend();
      bounded.resume();
      async.elapse(const Duration(seconds: 1));

      expect(system.calls, isEmpty);
      expect(system.active, isEmpty);
    });
  });

  test('a late register after the caller unregistered is taken off again', () {
    // Core review L-15 F15-2: register(K) answers after its timeout, when the
    // caller has already unregistered K; K must not stay on the system.
    fakeAsync((async) {
      final k = _key(LogicalKeyboardKey.keyK);
      final bounded = SuspendableHotKeyRegistrar(system);
      system.registerDelay = const Duration(seconds: 6);
      bounded.register(k).catchError((Object _) {});
      async.elapse(const Duration(seconds: 5));
      bounded.unregister(k);
      async.elapse(const Duration(seconds: 3));

      expect(system.active, isEmpty);
      expect(system.calls, [
        'register:${k.identifier}',
        // The caller's own unregister never reaches the system: K was not
        // registered by then (#541). Only the late-register undo does.
        'unregister:${k.identifier}',
      ]);
    });
  });

  test('an unregister that never answers fails after the step timeout', () {
    fakeAsync((async) {
      final bounded = SuspendableHotKeyRegistrar(system);
      final a = _key(LogicalKeyboardKey.keyA);
      bounded.register(a);
      async.flushMicrotasks();
      system.hangUnregister = true;
      Object? error;
      bounded.unregister(a).catchError((Object e) => error = e);
      async.elapse(const Duration(seconds: 6));

      expect(error, isA<TimeoutException>());
    });
  });

  group('HotkeyCaptureGuard listening', () {
    tearDown(HotkeyCaptureGuard.reset);

    test('notifies on the first begin and the last end only', () {
      final events = <bool>[];
      HotkeyCaptureGuard.setListeningListener(events.add);

      HotkeyCaptureGuard.beginListening();
      HotkeyCaptureGuard.beginListening();
      HotkeyCaptureGuard.endListening();
      expect(events, [true]);
      HotkeyCaptureGuard.endListening();

      expect(events, [true, false]);
      expect(HotkeyCaptureGuard.listening, isFalse);
      expect(HotkeyCaptureGuard.active, isFalse);
    });

    test('an extra end never drives the counters below zero', () {
      HotkeyCaptureGuard.endListening();
      HotkeyCaptureGuard.beginListening();

      expect(HotkeyCaptureGuard.listening, isTrue);
      expect(HotkeyCaptureGuard.active, isTrue);
    });

    test('a recorder listening past the limit gives the hotkeys back', () {
      // Core review L-14 F4: a recorder gone without dispose must not keep
      // every hotkey off the system until the next start.
      var now = DateTime(2026, 10, 31, 12);
      HotkeyCaptureGuard.clock = () => now;
      final events = <bool>[];
      HotkeyCaptureGuard.setListeningListener(events.add);
      HotkeyCaptureGuard.begin();
      HotkeyCaptureGuard.beginListening();

      now = now.add(kHotkeyCaptureListenLimit);
      expect(HotkeyCaptureGuard.releaseStale(now), isFalse);
      expect(HotkeyCaptureGuard.listening, isTrue);

      now = now.add(const Duration(minutes: 1));
      expect(HotkeyCaptureGuard.releaseStale(now), isTrue);
      expect(events, [true, false]);
      expect(HotkeyCaptureGuard.listening, isFalse);
      expect(HotkeyCaptureGuard.active, isTrue, reason: 'the plain begin');

      // The recorder ends after all: the counts stay balanced.
      HotkeyCaptureGuard.endListening();
      HotkeyCaptureGuard.end();
      expect(HotkeyCaptureGuard.active, isFalse);
      expect(events, [true, false]);
    });

    test('running out of the listening time tells the recorders once, and '
        'a late end cannot end a newer recorder', () {
      var now = DateTime(2026, 11, 2, 9);
      HotkeyCaptureGuard.clock = () => now;
      var expiries = 0;
      void onExpired() => expiries++;
      HotkeyCaptureGuard.listenLimitExpired.addListener(onExpired);
      addTearDown(
        () => HotkeyCaptureGuard.listenLimitExpired.removeListener(onExpired),
      );
      final oldRecorder = HotkeyCaptureGuard.beginListening();

      now = now.add(kHotkeyCaptureListenLimit + const Duration(seconds: 1));
      expect(HotkeyCaptureGuard.releaseStale(now), isTrue);
      expect(HotkeyCaptureGuard.releaseStale(now), isFalse);
      expect(expiries, 1);
      expect(HotkeyCaptureGuard.listening, isFalse);

      // The old recorder closes after a newer one started listening.
      final newRecorder = HotkeyCaptureGuard.beginListening();
      HotkeyCaptureGuard.endListening(oldRecorder);
      expect(HotkeyCaptureGuard.listening, isTrue);

      HotkeyCaptureGuard.endListening(newRecorder);
      expect(HotkeyCaptureGuard.listening, isFalse);
      expect(HotkeyCaptureGuard.active, isFalse);
    });

    test('nothing to release while no recorder listens', () {
      expect(HotkeyCaptureGuard.releaseStale(DateTime(2100)), isFalse);
    });

    test('the onboarding page scope keeps the hotkey registered', () {
      final events = <bool>[];
      HotkeyCaptureGuard.setListeningListener(events.add);

      HotkeyCaptureGuard.begin();

      expect(HotkeyCaptureGuard.active, isTrue);
      expect(HotkeyCaptureGuard.listening, isFalse);
      expect(events, isEmpty);
    });
  });
}
