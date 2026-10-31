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

  @override
  bool get supportsKeyUp => false;

  @override
  Future<void> register(
    HotKey hotKey, {
    HotKeyHandler? keyDownHandler,
    HotKeyHandler? keyUpHandler,
  }) async {
    if (refuse.contains(hotKey.identifier)) {
      throw PlatformException(code: 'hotkey_unavailable');
    }
    active[hotKey.identifier] = keyDownHandler;
  }

  @override
  Future<void> unregister(HotKey hotKey) {
    if (hangUnregister) return Completer<void>().future;
    active.remove(hotKey.identifier);
    return Future<void>.value();
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
      system.hangUnregister = true;
      bounded.unregister(_key(LogicalKeyboardKey.keyA));
      async.flushMicrotasks();
      expect(async.pendingTimers, isNotEmpty);

      bounded.dispose();

      expect(async.pendingTimers, isEmpty);
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
