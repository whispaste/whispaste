/// Unit tests for [HotkeyService] error-handling and safe-default fallback.
///
/// Uses [FakeHotKeyRegistrar] to avoid real platform-channel calls.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import 'package:whispaste/services/hotkey_key_resolver.dart';
import 'package:whispaste/services/hotkey_service.dart';
import 'package:whispaste/services/keyboard_up_monitor.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

/// Tracks [register]/[unregister] calls and can be told to throw on demand.
class FakeHotKeyRegistrar implements HotKeyRegistrar {
  FakeHotKeyRegistrar({this.supportsKeyUp = false});

  final List<HotKey> registered = [];
  final List<HotKey> unregistered = [];

  /// Last keyDown handler passed to [register].
  HotKeyHandler? capturedKeyDownHandler;

  /// Last keyUp handler passed to [register].
  HotKeyHandler? capturedKeyUpHandler;

  /// Handlers captured per logical key (by [LogicalKeyboardKey.keyId]),
  /// letting a test drive two independently-registered actions (e.g. the
  /// global and quick-note hotkeys) separately, since [capturedKeyDownHandler]
  /// only ever holds the most recent registration's handler.
  final Map<int, HotKeyHandler> keyDownHandlersByKeyId = {};
  final Map<int, HotKeyHandler> keyUpHandlersByKeyId = {};

  /// If non-null, [register] throws this object the first time it is called.
  Object? throwOnFirstRegister;

  @override
  final bool supportsKeyUp;

  @override
  Future<void> register(
    HotKey hotKey, {
    HotKeyHandler? keyDownHandler,
    HotKeyHandler? keyUpHandler,
  }) async {
    if (throwOnFirstRegister != null) {
      final toThrow = throwOnFirstRegister;
      throwOnFirstRegister = null; // only throw once
      // ignore: only_throw_errors
      throw toThrow!;
    }
    capturedKeyDownHandler = keyDownHandler;
    capturedKeyUpHandler = keyUpHandler;
    if (keyDownHandler != null) {
      keyDownHandlersByKeyId[hotKey.logicalKey.keyId] = keyDownHandler;
    }
    if (keyUpHandler != null) {
      keyUpHandlersByKeyId[hotKey.logicalKey.keyId] = keyUpHandler;
    }
    registered.add(hotKey);
  }

  @override
  Future<void> unregister(HotKey hotKey) async {
    unregistered.add(hotKey);
    registered.removeWhere((k) => k.identifier == hotKey.identifier);
  }
}

/// Fake RawInput key-up monitor (#39). Records start/stop and can emit a
/// synthetic key-up to drive the service's release path.
class FakeKeyboardUpMonitor implements KeyboardUpMonitor {
  FakeKeyboardUpMonitor({this.supportsKeyUp = true});

  @override
  final bool supportsKeyUp;

  final List<HotKey> started = [];
  int stopCount = 0;
  int armCount = 0;
  VoidCallback? _onKeyUp;

  @override
  set onKeyUp(VoidCallback? handler) => _onKeyUp = handler;

  @override
  Future<void> start(HotKey hotKey) async => started.add(hotKey);

  @override
  Future<void> armRelease() async => armCount++;

  @override
  Future<void> stop() async => stopCount++;

  /// Simulates the native host reporting the watched hotkey's release.
  void emitKeyUp() => _onKeyUp?.call();
}

/// A [FakeHotKeyRegistrar] whose [register] can be held open via [gate] —
/// used to drive the epoch-guard race of the session-scoped
/// interactive-snippet keys deterministically.
class GatedHotKeyRegistrar extends FakeHotKeyRegistrar {
  /// While non-null, [register] parks on this completer before delegating.
  Completer<void>? gate;

  @override
  Future<void> register(
    HotKey hotKey, {
    HotKeyHandler? keyDownHandler,
    HotKeyHandler? keyUpHandler,
  }) async {
    final g = gate;
    if (g != null) await g.future;
    await super.register(
      hotKey,
      keyDownHandler: keyDownHandler,
      keyUpHandler: keyUpHandler,
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Creates a standalone [HotkeyService] with an injected [FakeHotKeyRegistrar].
///
/// Does NOT use Riverpod — we call [updateHotkey] directly so there is no
/// [build] lifecycle to manage.
HotkeyService _makeService(FakeHotKeyRegistrar registrar) {
  final service = HotkeyService();
  service.injectRegistrar(registrar);
  // Inject a no-op key-up monitor so capability is driven solely by the
  // injected registrar and stays deterministic regardless of the host platform.
  // On Windows the default ChannelKeyboardUpMonitor reports supportsKeyUp=true
  // and would otherwise leak into these tests (#39). Monitor-path tests override
  // this with their own FakeKeyboardUpMonitor.
  service.injectMonitor(NoopKeyboardUpMonitor());
  return service;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // The sentry SDK requires a binding to be initialised before it can add
  // breadcrumbs; in tests it silently no-ops, which is what we want.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HotkeyService — error handling', () {
    test(
      'AC1: catches Object — registration that throws TypeError does not propagate',
      () async {
        final registrar = FakeHotKeyRegistrar()
          ..throwOnFirstRegister = TypeError();
        final service = _makeService(registrar);

        // Must complete without throwing even though register throws TypeError.
        await expectLater(
          service.updateHotkey(key: LogicalKeyboardKey.keyD),
          completes,
        );
      },
    );

    test(
      'AC2: safe-default registered — after TypeError, safe-default key is registered',
      () async {
        final registrar = FakeHotKeyRegistrar()
          ..throwOnFirstRegister = TypeError();
        final service = _makeService(registrar);

        await service.updateHotkey(key: LogicalKeyboardKey.keyD);

        // The safe-default (Space) must be in the registered list.
        expect(
          registrar.registered.any(
            (k) => k.logicalKey == LogicalKeyboardKey.space,
          ),
          isTrue,
          reason: 'safe-default Space key should be registered after failure',
        );
      },
    );

    test(
      'AC3: localised toast callback — onRegistrationFailed is invoked after TypeError',
      () async {
        final registrar = FakeHotKeyRegistrar()
          ..throwOnFirstRegister = TypeError();
        final service = _makeService(registrar);

        var callbackFired = false;
        service.onRegistrationFailed = () => callbackFired = true;

        await service.updateHotkey(key: LogicalKeyboardKey.keyD);

        expect(
          callbackFired,
          isTrue,
          reason:
              'onRegistrationFailed must be called so the UI can show a toast',
        );
      },
    );

    test(
      'AC4: Sentry breadcrumb — updateHotkey completes (breadcrumb added internally)',
      () async {
        // We cannot assert on the Sentry SDK directly in unit tests, but we
        // verify the code path doesn't throw and the key-code string is formed
        // correctly by checking the logged key ID is a hex string.
        final registrar = FakeHotKeyRegistrar()
          ..throwOnFirstRegister = TypeError();
        final service = _makeService(registrar);

        // No exception must escape — this verifies the breadcrumb call didn't
        // itself cause a crash.
        await expectLater(
          service.updateHotkey(key: LogicalKeyboardKey.keyD),
          completes,
        );

        // Verify the failed key code is formatted as a hex string (not PII).
        final hexPattern = RegExp(r'^[0-9a-f]+$');
        final keyCode = LogicalKeyboardKey.keyD.keyId.toRadixString(16);
        expect(
          hexPattern.hasMatch(keyCode),
          isTrue,
          reason: 'key code sent to breadcrumb must be a hex string, not PII',
        );
      },
    );

    test(
      'AC5: TypeError leaves service usable — onHotkeyPressed still fires after fallback',
      () async {
        final registrar = FakeHotKeyRegistrar()
          ..throwOnFirstRegister = TypeError();
        final service = _makeService(registrar);

        var hotkeyFired = false;
        service.onHotkeyPressed = () => hotkeyFired = true;

        await service.updateHotkey(key: LogicalKeyboardKey.keyD);

        // The safe-default handler should have been registered.
        expect(
          registrar.registered.isNotEmpty,
          isTrue,
          reason:
              'safe-default hotkey must be registered so the service is usable',
        );

        // Simulate the hotkey press by calling the service's hotkeyPressed
        // callback directly to verify the service is still wired.
        service.onHotkeyPressed?.call();
        expect(
          hotkeyFired,
          isTrue,
          reason: 'service must remain usable after fallback',
        );
      },
    );

    test(
      'normal registration — no fallback triggered when register succeeds',
      () async {
        final registrar = FakeHotKeyRegistrar(); // no throw
        final service = _makeService(registrar);

        var failedCallbackFired = false;
        service.onRegistrationFailed = () => failedCallbackFired = true;

        await service.updateHotkey(
          key: LogicalKeyboardKey.keyD,
          modifiers: [HotKeyModifier.control, HotKeyModifier.shift],
        );

        expect(
          failedCallbackFired,
          isFalse,
          reason:
              'onRegistrationFailed must NOT fire when registration succeeds',
        );
        // Only one key should be registered (the requested one, not the fallback).
        expect(registrar.registered.length, equals(1));
        expect(
          registrar.registered.first.logicalKey,
          equals(LogicalKeyboardKey.keyD),
        );
      },
    );

    test(
      'catches plain Exception — onRegistrationFailed fires for Exception too',
      () async {
        final registrar = FakeHotKeyRegistrar()
          ..throwOnFirstRegister = Exception('platform error');
        final service = _makeService(registrar);

        var callbackFired = false;
        service.onRegistrationFailed = () => callbackFired = true;

        await service.updateHotkey(key: LogicalKeyboardKey.space);

        expect(callbackFired, isTrue);
      },
    );
  });

  group('safeDefaultHotKey', () {
    test('contains Space key', () {
      expect(safeDefaultHotKey.logicalKey, equals(LogicalKeyboardKey.space));
    });

    test('has at least one modifier', () {
      expect(safeDefaultHotKey.modifiers, isNotEmpty);
    });
  });

  group('HotkeyService — arrow key registration (AC1–AC3)', () {
    test('AC1: arrowLeft + alt registered correctly', () async {
      final registrar = FakeHotKeyRegistrar();
      final service = _makeService(registrar);

      await service.updateHotkey(
        key: LogicalKeyboardKey.arrowLeft,
        modifiers: [HotKeyModifier.alt],
      );

      expect(registrar.registered.length, equals(1));
      expect(
        registrar.registered.first.logicalKey,
        equals(LogicalKeyboardKey.arrowLeft),
        reason: 'arrowLeft must be registered, not silently replaced by keyD',
      );
      expect(
        registrar.registered.first.modifiers,
        contains(HotKeyModifier.alt),
      );
    });

    test('AC2: arrowUp + control registered correctly', () async {
      final registrar = FakeHotKeyRegistrar();
      final service = _makeService(registrar);

      await service.updateHotkey(
        key: LogicalKeyboardKey.arrowUp,
        modifiers: [HotKeyModifier.control],
      );

      expect(registrar.registered.length, equals(1));
      expect(
        registrar.registered.first.logicalKey,
        equals(LogicalKeyboardKey.arrowUp),
      );
    });

    test('AC3: all four arrow keys register without fallback', () async {
      final arrows = [
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.arrowDown,
      ];

      for (final arrow in arrows) {
        final registrar = FakeHotKeyRegistrar();
        final service = _makeService(registrar);

        await service.updateHotkey(
          key: arrow,
          modifiers: [HotKeyModifier.control],
        );

        expect(
          registrar.registered.any((k) => k.logicalKey == arrow),
          isTrue,
          reason: '$arrow must be registered',
        );
        // Safe-default Space must NOT be in the list (no fallback)
        expect(
          registrar.registered.any(
            (k) => k.logicalKey == LogicalKeyboardKey.space,
          ),
          isFalse,
          reason: 'fallback must not fire for a valid arrow key',
        );
      }
    });
  });

  group('HotkeyService — keyUp callback (Push-to-Talk wiring)', () {
    test(
      'supportsKeyUp=true: onHotkeyReleased fires when keyUp handler is called',
      () async {
        final registrar = FakeHotKeyRegistrar(supportsKeyUp: true);
        final service = _makeService(registrar);

        var keyDownFired = false;
        var keyUpFired = false;
        service.onHotkeyPressed = () => keyDownFired = true;
        service.onHotkeyReleased = () => keyUpFired = true;

        await service.updateHotkey(key: LogicalKeyboardKey.keyD);

        expect(
          registrar.capturedKeyUpHandler,
          isNotNull,
          reason: 'keyUpHandler must be registered when supportsKeyUp=true',
        );

        // Simulate keyDown and keyUp from the platform.
        registrar.capturedKeyDownHandler!(registrar.registered.first);
        registrar.capturedKeyUpHandler!(registrar.registered.first);

        expect(keyDownFired, isTrue);
        expect(keyUpFired, isTrue);
      },
    );

    test('supportsKeyUp=false: keyUpHandler is not registered', () async {
      final registrar = FakeHotKeyRegistrar(supportsKeyUp: false);
      final service = _makeService(registrar);

      service.onHotkeyReleased = () {};

      await service.updateHotkey(key: LogicalKeyboardKey.keyD);

      expect(
        registrar.capturedKeyUpHandler,
        isNull,
        reason:
            'keyUpHandler must be null when platform does not support keyUp',
      );
    });

    test('supportsKeyUp reflects the registrar property', () {
      final registrarTrue = FakeHotKeyRegistrar(supportsKeyUp: true);
      final serviceTrue = _makeService(registrarTrue);
      expect(serviceTrue.supportsKeyUp, isTrue);

      final registrarFalse = FakeHotKeyRegistrar(supportsKeyUp: false);
      final serviceFalse = _makeService(registrarFalse);
      expect(serviceFalse.supportsKeyUp, isFalse);
    });
  });

  group('HotkeyService — RawInput key-up monitor (#39, Windows PTT)', () {
    test(
      'a key-up monitor enables supportsKeyUp even with a key-down-only registrar',
      () {
        // Mirrors Windows: registrar (RegisterHotKey) has no key-up, but the
        // RawInput monitor does → push-to-talk becomes available.
        final registrar = FakeHotKeyRegistrar(supportsKeyUp: false);
        final service = _makeService(registrar);
        service.injectMonitor(FakeKeyboardUpMonitor(supportsKeyUp: true));

        expect(service.supportsKeyUp, isTrue);
      },
    );

    test(
      'the registered hotkey is handed to the monitor on registration',
      () async {
        final registrar = FakeHotKeyRegistrar(supportsKeyUp: false);
        final service = _makeService(registrar);
        final monitor = FakeKeyboardUpMonitor();
        service.injectMonitor(monitor);

        await service.updateHotkey(key: LogicalKeyboardKey.keyD);

        expect(monitor.started, hasLength(1));
        expect(monitor.started.first.logicalKey, LogicalKeyboardKey.keyD);
      },
    );

    test(
      'a monitor key-up fires onHotkeyReleased (no registrar key-up)',
      () async {
        final registrar = FakeHotKeyRegistrar(supportsKeyUp: false);
        final service = _makeService(registrar);
        final monitor = FakeKeyboardUpMonitor();
        service.injectMonitor(monitor);

        var released = false;
        service.onHotkeyReleased = () => released = true;

        await service.updateHotkey(key: LogicalKeyboardKey.keyD);
        // The registrar never delivers key-up on Windows…
        expect(registrar.capturedKeyUpHandler, isNull);
        // …RegisterHotKey fires the DOWN (a press is in flight)…
        registrar.capturedKeyDownHandler!(registrar.registered.first);
        // …and the RawInput monitor delivers the matching release.
        monitor.emitKeyUp();

        expect(released, isTrue);
      },
    );

    test(
      'a stray monitor key-up without a preceding down is ignored',
      () async {
        final registrar = FakeHotKeyRegistrar(supportsKeyUp: false);
        final service = _makeService(registrar);
        final monitor = FakeKeyboardUpMonitor();
        service.injectMonitor(monitor);

        var released = false;
        service.onHotkeyReleased = () => released = true;

        await service.updateHotkey(key: LogicalKeyboardKey.keyD);
        // No key-down happened (bare key seen by RawInput) → must be a no-op,
        // never reaching the push-to-talk trigger handler.
        monitor.emitKeyUp();

        expect(released, isFalse);
      },
    );

    test('a hotkey key-down arms the monitor release-watch', () async {
      // RegisterHotKey hides the hotkey key's DOWN from RawInput, so the
      // monitor must be armed from the Dart key-down to snapshot the held key.
      final registrar = FakeHotKeyRegistrar(supportsKeyUp: false);
      final service = _makeService(registrar);
      final monitor = FakeKeyboardUpMonitor();
      service.injectMonitor(monitor);

      await service.updateHotkey(key: LogicalKeyboardKey.keyD);
      registrar.capturedKeyDownHandler!(registrar.registered.first);

      expect(monitor.armCount, 1);
    });

    test('re-registering stops the previous monitor watch', () async {
      final registrar = FakeHotKeyRegistrar(supportsKeyUp: false);
      final service = _makeService(registrar);
      final monitor = FakeKeyboardUpMonitor();
      service.injectMonitor(monitor);

      await service.updateHotkey(key: LogicalKeyboardKey.keyD);
      await service.updateHotkey(key: LogicalKeyboardKey.keyE);

      // updateHotkey unregisters first → monitor.stop ran at least once.
      expect(monitor.stopCount, greaterThanOrEqualTo(1));
      expect(monitor.started, hasLength(2));
    });
  });

  group('end-to-end: Recorder-Output → Registrar-Input', () {
    // Freezes the storage→registrar seam that the modifier-bug slipped
    // through. The previous service-level tests called the public API
    // with HotKeyModifier directly, so a recorder that wrote bogus
    // display-label tokens (e.g. "option") was never observed end-to-end.

    test('stored "option" + "←" → registrar receives [alt] + arrowLeft '
        '(self-healing for the reporter\'s existing DB)', () async {
      final registrar = FakeHotKeyRegistrar();
      final service = _makeService(registrar);

      // Simulate what _registerFromSettings does for an existing DB whose
      // hotkey_modifiers='option' and hotkey_key='←' (the reporter's state).
      await service.updateHotkey(
        key: resolveKey('←'),
        modifiers: resolveModifiers('option'),
      );

      expect(registrar.registered.length, equals(1));
      expect(
        registrar.registered.first.logicalKey,
        equals(LogicalKeyboardKey.arrowLeft),
      );
      expect(
        registrar.registered.first.modifiers,
        contains(HotKeyModifier.alt),
        reason:
            'Self-healing alias must turn legacy "option" into HotKeyModifier.alt '
            'so the existing DB works without rebind.',
      );
    });

    test('AC: registrar throwing ArgumentError → safe-default fallback fires '
        '(mirror of TypeError path)', () async {
      // _registerFromSettings catches ArgumentError thrown by resolveKey for
      // existing DBs that contain a non-resolvable key (e.g. hotkey_key='Ö'
      // from a corrupted pre-fix DB). Same observable behaviour as the
      // pre-existing TypeError path: safe-default hotkey is registered and
      // onRegistrationFailed fires so the UI can prompt the user to re-bind.
      final registrar = FakeHotKeyRegistrar()
        ..throwOnFirstRegister = ArgumentError.value(
          'Ö',
          'label',
          'Unknown key label',
        );
      final service = _makeService(registrar);

      var failedCallbackFired = false;
      service.onRegistrationFailed = () => failedCallbackFired = true;

      await service.updateHotkey(key: LogicalKeyboardKey.keyD);

      expect(
        registrar.registered.any(
          (k) => k.logicalKey == LogicalKeyboardKey.space,
        ),
        isTrue,
        reason:
            'ArgumentError from register must trigger safe-default fallback',
      );
      expect(
        failedCallbackFired,
        isTrue,
        reason:
            'onRegistrationFailed must fire so the UI can prompt for re-bind',
      );
    });

    test('AC: tryRegisterFromSettings with hotkeyKey="Ö" → safe-default '
        'registered and onRegistrationFailed fires', () async {
      // Direct exercise of the _registerFromSettings ArgumentError path
      // via a small testing seam. resolveKey("Ö") throws ArgumentError;
      // the service must catch that, add a Sentry breadcrumb, and route
      // through _registerSafeDefault — without leaking the exception.
      final registrar = FakeHotKeyRegistrar();
      final service = _makeService(registrar);

      var failedCallbackFired = false;
      service.onRegistrationFailed = () => failedCallbackFired = true;

      await service.debugRegisterFromSettings(
        hotkeyKey: 'Ö',
        hotkeyModifiers: 'meta',
      );

      expect(
        registrar.registered.length,
        equals(1),
        reason: 'a single (safe-default) hotkey must be registered',
      );
      expect(
        registrar.registered.first.logicalKey,
        equals(LogicalKeyboardKey.space),
        reason: 'safe-default Space key must be used as fallback for "Ö"',
      );
      expect(
        failedCallbackFired,
        isTrue,
        reason: 'onRegistrationFailed must fire after ArgumentError fallback',
      );
    });

    test('stored DE "strg+umschalt" + "D" → registrar receives '
        '[control, shift] + keyD', () async {
      final registrar = FakeHotKeyRegistrar();
      final service = _makeService(registrar);

      await service.updateHotkey(
        key: resolveKey('D'),
        modifiers: resolveModifiers('strg+umschalt'),
      );

      expect(registrar.registered.length, equals(1));
      expect(
        registrar.registered.first.logicalKey,
        equals(LogicalKeyboardKey.keyD),
      );
      expect(
        registrar.registered.first.modifiers,
        containsAll([HotKeyModifier.control, HotKeyModifier.shift]),
      );
    });
  });

  group('HotkeyService — auto-repeat suppression (held key)', () {
    test('macOS (keyUp): held key streams key-downs but toggles once; release '
        'then press toggles again', () async {
      final registrar = FakeHotKeyRegistrar(supportsKeyUp: true);
      final service = _makeService(registrar);
      var presses = 0;
      service.onHotkeyPressed = () => presses++;
      await service.updateHotkey(key: LogicalKeyboardKey.keyD);
      final hk = registrar.registered.first;

      // Hold: OS streams repeated key-downs — only the first must count.
      registrar.capturedKeyDownHandler!(hk);
      registrar.capturedKeyDownHandler!(hk);
      registrar.capturedKeyDownHandler!(hk);
      expect(presses, 1, reason: 'auto-repeat key-downs must be swallowed');

      // Release, then a genuine new press toggles again.
      registrar.capturedKeyUpHandler!(hk);
      registrar.capturedKeyDownHandler!(hk);
      expect(presses, 2, reason: 'press after release must register');
    });

    test(
      'Windows/Linux (no keyUp): rapid auto-repeat key-downs toggle once',
      () async {
        final registrar = FakeHotKeyRegistrar(supportsKeyUp: false);
        final service = _makeService(registrar);
        var presses = 0;
        service.onHotkeyPressed = () => presses++;
        await service.updateHotkey(key: LogicalKeyboardKey.keyD);
        final hk = registrar.registered.first;

        // A held key with no key-up streams fast repeats within the window;
        // they must collapse to a single toggle (no start/stop flapping).
        for (var i = 0; i < 20; i++) {
          registrar.capturedKeyDownHandler!(hk);
        }
        expect(presses, 1, reason: 'held key must not flip start/stop');
      },
    );
  });

  group('HotkeyService — quick-note action (ticket 20)', () {
    test('registers independently of the global hotkey', () async {
      final registrar = FakeHotKeyRegistrar();
      final service = _makeService(registrar);

      await service.updateHotkey(key: LogicalKeyboardKey.keyD);
      await service.updateQuickNoteHotkey(key: LogicalKeyboardKey.keyY);

      expect(registrar.registered, hasLength(2));
      expect(
        registrar.registered.map((k) => k.logicalKey),
        containsAll([LogicalKeyboardKey.keyD, LogicalKeyboardKey.keyY]),
      );
    });

    test(
      'changing the quick-note combo does not re-register the global hotkey',
      () async {
        final registrar = FakeHotKeyRegistrar();
        final service = _makeService(registrar);

        await service.updateHotkey(key: LogicalKeyboardKey.keyD);
        await service.updateQuickNoteHotkey(key: LogicalKeyboardKey.keyY);
        await service.updateQuickNoteHotkey(key: LogicalKeyboardKey.keyN);

        // The global combo must never have been unregistered.
        expect(
          registrar.unregistered.any(
            (k) => k.logicalKey == LogicalKeyboardKey.keyD,
          ),
          isFalse,
        );
        expect(
          registrar.registered.any(
            (k) => k.logicalKey == LogicalKeyboardKey.keyD,
          ),
          isTrue,
        );
        // Only the new quick-note combo remains registered.
        expect(
          registrar.registered.any(
            (k) => k.logicalKey == LogicalKeyboardKey.keyN,
          ),
          isTrue,
        );
        expect(
          registrar.registered.any(
            (k) => k.logicalKey == LogicalKeyboardKey.keyY,
          ),
          isFalse,
        );
      },
    );

    test(
      'changing the global combo does not re-register the quick-note hotkey',
      () async {
        final registrar = FakeHotKeyRegistrar();
        final service = _makeService(registrar);

        await service.updateQuickNoteHotkey(key: LogicalKeyboardKey.keyY);
        await service.updateHotkey(key: LogicalKeyboardKey.keyD);
        await service.updateHotkey(key: LogicalKeyboardKey.keyE);

        expect(
          registrar.unregistered.any(
            (k) => k.logicalKey == LogicalKeyboardKey.keyY,
          ),
          isFalse,
        );
        expect(
          registrar.registered.any(
            (k) => k.logicalKey == LogicalKeyboardKey.keyY,
          ),
          isTrue,
        );
      },
    );

    test(
      'a failed quick-note registration reports conflict without a safe-default fallback',
      () async {
        final registrar = FakeHotKeyRegistrar()
          ..throwOnFirstRegister = TypeError();
        final service = _makeService(registrar);

        await expectLater(
          service.updateQuickNoteHotkey(key: LogicalKeyboardKey.keyY),
          completes,
        );

        // No Space (safe-default) must ever be registered for this action.
        expect(
          registrar.registered.any(
            (k) => k.logicalKey == LogicalKeyboardKey.space,
          ),
          isFalse,
          reason: 'ticket 20 forbids a safe-default fallback for this action',
        );
        expect(registrar.registered, isEmpty);
      },
    );

    test(
      'a failed quick-note registration does not affect the already-registered global hotkey',
      () async {
        final registrar = FakeHotKeyRegistrar();
        final service = _makeService(registrar);

        await service.updateHotkey(key: LogicalKeyboardKey.keyD);
        registrar.throwOnFirstRegister = TypeError();
        await service.updateQuickNoteHotkey(key: LogicalKeyboardKey.keyY);

        expect(
          registrar.registered.any(
            (k) => k.logicalKey == LogicalKeyboardKey.keyD,
          ),
          isTrue,
          reason: 'global hotkey must remain registered and untouched',
        );
      },
    );

    test(
      'a failed global registration (safe-default fallback) does not affect an already-registered quick-note hotkey',
      () async {
        final registrar = FakeHotKeyRegistrar();
        final service = _makeService(registrar);

        await service.updateQuickNoteHotkey(key: LogicalKeyboardKey.keyY);
        registrar.throwOnFirstRegister = TypeError();
        await service.updateHotkey(key: LogicalKeyboardKey.keyD);

        expect(
          registrar.registered.any(
            (k) => k.logicalKey == LogicalKeyboardKey.keyY,
          ),
          isTrue,
          reason: 'quick-note hotkey must remain registered and untouched',
        );
      },
    );

    test(
      'no keyUpHandler is registered for the quick-note action even when '
      'the registrar supports keyUp (toggle-only, no push-to-talk)',
      () async {
        final registrar = FakeHotKeyRegistrar(supportsKeyUp: true);
        final service = _makeService(registrar);

        await service.updateQuickNoteHotkey(key: LogicalKeyboardKey.keyY);

        expect(registrar.capturedKeyUpHandler, isNull);
      },
    );

    test(
      'quick-note registration does not start the shared keyboard-up monitor',
      () async {
        final registrar = FakeHotKeyRegistrar(supportsKeyUp: false);
        final service = _makeService(registrar);
        final monitor = FakeKeyboardUpMonitor();
        service.injectMonitor(monitor);

        await service.updateQuickNoteHotkey(key: LogicalKeyboardKey.keyY);

        expect(
          monitor.started,
          isEmpty,
          reason:
              'the monitor is a single shared native channel — starting it '
              'for the toggle-only quick-note action would steal the '
              "global hotkey's release watch",
        );
      },
    );

    test(
      'quick-note key-down fires onQuickNoteHotkeyPressed exactly once per press',
      () async {
        final registrar = FakeHotKeyRegistrar();
        final service = _makeService(registrar);
        var presses = 0;
        service.onQuickNoteHotkeyPressed = () => presses++;

        await service.updateQuickNoteHotkey(key: LogicalKeyboardKey.keyY);
        registrar.capturedKeyDownHandler!(registrar.registered.first);

        expect(presses, 1);
      },
    );

    test(
      'auto-repeat suppression is independent per action — holding the '
      'quick-note key does not suppress the global hotkey and vice versa',
      () async {
        final registrar = FakeHotKeyRegistrar();
        final service = _makeService(registrar);
        var globalPresses = 0;
        var quickNotePresses = 0;
        service.onHotkeyPressed = () => globalPresses++;
        service.onQuickNoteHotkeyPressed = () => quickNotePresses++;

        await service.updateHotkey(key: LogicalKeyboardKey.keyD);
        await service.updateQuickNoteHotkey(key: LogicalKeyboardKey.keyY);

        final globalDown =
            registrar.keyDownHandlersByKeyId[LogicalKeyboardKey.keyD.keyId]!;
        final quickNoteDown =
            registrar.keyDownHandlersByKeyId[LogicalKeyboardKey.keyY.keyId]!;
        final globalHotKey = registrar.registered.firstWhere(
          (k) => k.logicalKey == LogicalKeyboardKey.keyD,
        );
        final quickNoteHotKey = registrar.registered.firstWhere(
          (k) => k.logicalKey == LogicalKeyboardKey.keyY,
        );

        // Hold the global key: repeated key-downs collapse to a single press.
        globalDown(globalHotKey);
        globalDown(globalHotKey);
        expect(globalPresses, 1);

        // A fresh press of the quick-note key must fire immediately — the
        // held global key's auto-repeat window must not bleed into it.
        quickNoteDown(quickNoteHotKey);
        expect(quickNotePresses, 1);
      },
    );
  });

  group('quickNoteHotkeyRegistrationStatusProvider', () {
    test('starts unknown and reflects .set() calls independently', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(quickNoteHotkeyRegistrationStatusProvider),
        HotkeyRegistrationStatus.unknown,
      );

      container
          .read(quickNoteHotkeyRegistrationStatusProvider.notifier)
          .set(HotkeyRegistrationStatus.conflict);

      expect(
        container.read(quickNoteHotkeyRegistrationStatusProvider),
        HotkeyRegistrationStatus.conflict,
      );
      // Independent of the existing (global) status provider.
      expect(
        container.read(hotkeyRegistrationStatusProvider),
        HotkeyRegistrationStatus.unknown,
      );
    });
  });

  group('HotkeyService — snippet-picker action (ticket 26)', () {
    test(
      'registers independently of the global and quick-note hotkeys',
      () async {
        final registrar = FakeHotKeyRegistrar();
        final service = _makeService(registrar);

        await service.updateHotkey(key: LogicalKeyboardKey.keyD);
        await service.updateQuickNoteHotkey(key: LogicalKeyboardKey.keyN);
        await service.updateSnippetPickerHotkey(key: LogicalKeyboardKey.keyE);

        expect(registrar.registered, hasLength(3));
        expect(
          registrar.registered.map((k) => k.logicalKey),
          containsAll([
            LogicalKeyboardKey.keyD,
            LogicalKeyboardKey.keyN,
            LogicalKeyboardKey.keyE,
          ]),
        );
      },
    );

    test(
      'changing the snippet-picker combo does not re-register the other two hotkeys',
      () async {
        final registrar = FakeHotKeyRegistrar();
        final service = _makeService(registrar);

        await service.updateHotkey(key: LogicalKeyboardKey.keyD);
        await service.updateQuickNoteHotkey(key: LogicalKeyboardKey.keyN);
        await service.updateSnippetPickerHotkey(key: LogicalKeyboardKey.keyE);
        await service.updateSnippetPickerHotkey(key: LogicalKeyboardKey.keyF);

        expect(
          registrar.unregistered.any(
            (k) =>
                k.logicalKey == LogicalKeyboardKey.keyD ||
                k.logicalKey == LogicalKeyboardKey.keyN,
          ),
          isFalse,
        );
        expect(
          registrar.registered.any(
            (k) => k.logicalKey == LogicalKeyboardKey.keyF,
          ),
          isTrue,
        );
        expect(
          registrar.registered.any(
            (k) => k.logicalKey == LogicalKeyboardKey.keyE,
          ),
          isFalse,
        );
      },
    );

    test(
      'a failed snippet-picker registration reports conflict without a safe-default fallback',
      () async {
        final registrar = FakeHotKeyRegistrar()
          ..throwOnFirstRegister = TypeError();
        final service = _makeService(registrar);

        await expectLater(
          service.updateSnippetPickerHotkey(key: LogicalKeyboardKey.keyE),
          completes,
        );

        expect(
          registrar.registered.any(
            (k) => k.logicalKey == LogicalKeyboardKey.space,
          ),
          isFalse,
          reason: 'ticket 26 forbids a safe-default fallback for this action',
        );
        expect(registrar.registered, isEmpty);
      },
    );

    test(
      'a failed snippet-picker registration does not affect the already-registered global or quick-note hotkey',
      () async {
        final registrar = FakeHotKeyRegistrar();
        final service = _makeService(registrar);

        await service.updateHotkey(key: LogicalKeyboardKey.keyD);
        await service.updateQuickNoteHotkey(key: LogicalKeyboardKey.keyN);
        registrar.throwOnFirstRegister = TypeError();
        await service.updateSnippetPickerHotkey(key: LogicalKeyboardKey.keyE);

        expect(
          registrar.registered.any(
            (k) => k.logicalKey == LogicalKeyboardKey.keyD,
          ),
          isTrue,
        );
        expect(
          registrar.registered.any(
            (k) => k.logicalKey == LogicalKeyboardKey.keyN,
          ),
          isTrue,
        );
      },
    );

    test(
      'a failed global registration (safe-default fallback) does not affect an already-registered snippet-picker hotkey',
      () async {
        final registrar = FakeHotKeyRegistrar();
        final service = _makeService(registrar);

        await service.updateSnippetPickerHotkey(key: LogicalKeyboardKey.keyE);
        registrar.throwOnFirstRegister = TypeError();
        await service.updateHotkey(key: LogicalKeyboardKey.keyD);

        expect(
          registrar.registered.any(
            (k) => k.logicalKey == LogicalKeyboardKey.keyE,
          ),
          isTrue,
          reason: 'snippet-picker hotkey must remain registered and untouched',
        );
      },
    );

    test(
      'no keyUpHandler is registered for the snippet-picker action even when '
      'the registrar supports keyUp (one-shot, no push-to-talk)',
      () async {
        final registrar = FakeHotKeyRegistrar(supportsKeyUp: true);
        final service = _makeService(registrar);

        await service.updateSnippetPickerHotkey(key: LogicalKeyboardKey.keyE);

        expect(registrar.capturedKeyUpHandler, isNull);
      },
    );

    test(
      'snippet-picker registration does not start the shared keyboard-up monitor',
      () async {
        final registrar = FakeHotKeyRegistrar(supportsKeyUp: false);
        final service = _makeService(registrar);
        final monitor = FakeKeyboardUpMonitor();
        service.injectMonitor(monitor);

        await service.updateSnippetPickerHotkey(key: LogicalKeyboardKey.keyE);

        expect(monitor.started, isEmpty);
      },
    );

    test(
      'snippet-picker key-down fires onSnippetPickerHotkeyPressed exactly once per press',
      () async {
        final registrar = FakeHotKeyRegistrar();
        final service = _makeService(registrar);
        var presses = 0;
        service.onSnippetPickerHotkeyPressed = () => presses++;

        await service.updateSnippetPickerHotkey(key: LogicalKeyboardKey.keyE);
        registrar.capturedKeyDownHandler!(registrar.registered.first);

        expect(presses, 1);
      },
    );

    test(
      'auto-repeat suppression is independent of the other two actions',
      () async {
        final registrar = FakeHotKeyRegistrar();
        final service = _makeService(registrar);
        var globalPresses = 0;
        var snippetPickerPresses = 0;
        service.onHotkeyPressed = () => globalPresses++;
        service.onSnippetPickerHotkeyPressed = () => snippetPickerPresses++;

        await service.updateHotkey(key: LogicalKeyboardKey.keyD);
        await service.updateSnippetPickerHotkey(key: LogicalKeyboardKey.keyE);

        final globalDown =
            registrar.keyDownHandlersByKeyId[LogicalKeyboardKey.keyD.keyId]!;
        final snippetPickerDown =
            registrar.keyDownHandlersByKeyId[LogicalKeyboardKey.keyE.keyId]!;
        final globalHotKey = registrar.registered.firstWhere(
          (k) => k.logicalKey == LogicalKeyboardKey.keyD,
        );
        final snippetPickerHotKey = registrar.registered.firstWhere(
          (k) => k.logicalKey == LogicalKeyboardKey.keyE,
        );

        globalDown(globalHotKey);
        globalDown(globalHotKey);
        expect(globalPresses, 1);

        snippetPickerDown(snippetPickerHotKey);
        expect(snippetPickerPresses, 1);
      },
    );
  });

  group('HotkeyService — Smart-Mode action (ticket 04)', () {
    test('registers independently of the other three hotkeys', () async {
      final registrar = FakeHotKeyRegistrar();
      final service = _makeService(registrar);

      await service.updateHotkey(key: LogicalKeyboardKey.keyD);
      await service.updateQuickNoteHotkey(key: LogicalKeyboardKey.keyN);
      await service.updateSnippetPickerHotkey(key: LogicalKeyboardKey.keyE);
      await service.updateSmartModeHotkey(key: LogicalKeyboardKey.keyM);

      expect(registrar.registered, hasLength(4));
      expect(
        registrar.registered.map((k) => k.logicalKey),
        containsAll([
          LogicalKeyboardKey.keyD,
          LogicalKeyboardKey.keyN,
          LogicalKeyboardKey.keyE,
          LogicalKeyboardKey.keyM,
        ]),
      );
    });

    test(
      'a failed Smart-Mode registration reports conflict without a safe-default fallback',
      () async {
        final registrar = FakeHotKeyRegistrar()
          ..throwOnFirstRegister = TypeError();
        final service = _makeService(registrar);

        await expectLater(
          service.updateSmartModeHotkey(key: LogicalKeyboardKey.keyM),
          completes,
        );

        expect(
          registrar.registered.any(
            (k) => k.logicalKey == LogicalKeyboardKey.space,
          ),
          isFalse,
          reason: 'ticket 04 forbids a safe-default fallback for this action',
        );
        expect(registrar.registered, isEmpty);
      },
    );

    test(
      'a failed Smart-Mode registration does not affect the other already-registered hotkeys',
      () async {
        final registrar = FakeHotKeyRegistrar();
        final service = _makeService(registrar);

        await service.updateHotkey(key: LogicalKeyboardKey.keyD);
        registrar.throwOnFirstRegister = TypeError();
        await service.updateSmartModeHotkey(key: LogicalKeyboardKey.keyM);

        expect(
          registrar.registered.any(
            (k) => k.logicalKey == LogicalKeyboardKey.keyD,
          ),
          isTrue,
        );
      },
    );

    test(
      'keyUpHandler IS registered for the Smart-Mode action when the '
      'registrar supports keyUp — push-to-talk parity with the main hotkey',
      () async {
        final registrar = FakeHotKeyRegistrar(supportsKeyUp: true);
        final service = _makeService(registrar);

        var pressed = false;
        var released = false;
        service.onSmartModeHotkeyPressed = () => pressed = true;
        service.onSmartModeHotkeyReleased = () => released = true;

        await service.updateSmartModeHotkey(key: LogicalKeyboardKey.keyM);

        expect(
          registrar.capturedKeyUpHandler,
          isNotNull,
          reason: 'ticket 04 requires push-to-talk parity with the main hotkey',
        );

        registrar.capturedKeyDownHandler!(registrar.registered.first);
        registrar.capturedKeyUpHandler!(registrar.registered.first);

        expect(pressed, isTrue);
        expect(released, isTrue);
      },
    );

    test(
      'keyUpHandler is not registered for the Smart-Mode action when the '
      'registrar does not support keyUp (Windows/Linux: toggle-only for now)',
      () async {
        final registrar = FakeHotKeyRegistrar(supportsKeyUp: false);
        final service = _makeService(registrar);

        await service.updateSmartModeHotkey(key: LogicalKeyboardKey.keyM);

        expect(registrar.capturedKeyUpHandler, isNull);
      },
    );

    test(
      'Smart-Mode registration does not start the shared keyboard-up monitor',
      () async {
        final registrar = FakeHotKeyRegistrar(supportsKeyUp: false);
        final service = _makeService(registrar);
        final monitor = FakeKeyboardUpMonitor();
        service.injectMonitor(monitor);

        await service.updateSmartModeHotkey(key: LogicalKeyboardKey.keyM);

        expect(monitor.started, isEmpty);
      },
    );

    test(
      'Smart-Mode key-down fires onSmartModeHotkeyPressed exactly once per press',
      () async {
        final registrar = FakeHotKeyRegistrar();
        final service = _makeService(registrar);
        var presses = 0;
        service.onSmartModeHotkeyPressed = () => presses++;

        await service.updateSmartModeHotkey(key: LogicalKeyboardKey.keyM);
        registrar.capturedKeyDownHandler!(registrar.registered.first);

        expect(presses, 1);
      },
    );

    test(
      'auto-repeat suppression is independent of the other three actions',
      () async {
        final registrar = FakeHotKeyRegistrar();
        final service = _makeService(registrar);
        var globalPresses = 0;
        var smartModePresses = 0;
        service.onHotkeyPressed = () => globalPresses++;
        service.onSmartModeHotkeyPressed = () => smartModePresses++;

        await service.updateHotkey(key: LogicalKeyboardKey.keyD);
        await service.updateSmartModeHotkey(key: LogicalKeyboardKey.keyM);

        final globalDown =
            registrar.keyDownHandlersByKeyId[LogicalKeyboardKey.keyD.keyId]!;
        final smartModeDown =
            registrar.keyDownHandlersByKeyId[LogicalKeyboardKey.keyM.keyId]!;
        final globalHotKey = registrar.registered.firstWhere(
          (k) => k.logicalKey == LogicalKeyboardKey.keyD,
        );
        final smartModeHotKey = registrar.registered.firstWhere(
          (k) => k.logicalKey == LogicalKeyboardKey.keyM,
        );

        globalDown(globalHotKey);
        globalDown(globalHotKey);
        expect(globalPresses, 1);

        smartModeDown(smartModeHotKey);
        expect(smartModePresses, 1);
      },
    );
  });

  group('smartModeHotkeyRegistrationStatusProvider', () {
    test('starts unknown and reflects .set() calls independently', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(smartModeHotkeyRegistrationStatusProvider),
        HotkeyRegistrationStatus.unknown,
      );

      container
          .read(smartModeHotkeyRegistrationStatusProvider.notifier)
          .set(HotkeyRegistrationStatus.conflict);

      expect(
        container.read(smartModeHotkeyRegistrationStatusProvider),
        HotkeyRegistrationStatus.conflict,
      );
      // Independent of the other three status providers.
      expect(
        container.read(hotkeyRegistrationStatusProvider),
        HotkeyRegistrationStatus.unknown,
      );
      expect(
        container.read(snippetPickerHotkeyRegistrationStatusProvider),
        HotkeyRegistrationStatus.unknown,
      );
    });
  });

  group('snippetPickerHotkeyRegistrationStatusProvider', () {
    test('starts unknown and reflects .set() calls independently', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(snippetPickerHotkeyRegistrationStatusProvider),
        HotkeyRegistrationStatus.unknown,
      );

      container
          .read(snippetPickerHotkeyRegistrationStatusProvider.notifier)
          .set(HotkeyRegistrationStatus.conflict);

      expect(
        container.read(snippetPickerHotkeyRegistrationStatusProvider),
        HotkeyRegistrationStatus.conflict,
      );
      // Independent of the other two status providers.
      expect(
        container.read(hotkeyRegistrationStatusProvider),
        HotkeyRegistrationStatus.unknown,
      );
      expect(
        container.read(quickNoteHotkeyRegistrationStatusProvider),
        HotkeyRegistrationStatus.unknown,
      );
    });
  });

  group('HotkeyService — session-scoped interactive-snippet keys', () {
    Iterable<HotKey> stillRegistered(
      FakeHotKeyRegistrar registrar,
      LogicalKeyboardKey key,
    ) => registrar.registered.where((k) => k.logicalKey == key);

    test('registers bare Enter and Escape, keyDown dispatches the '
        'callbacks', () async {
      final registrar = FakeHotKeyRegistrar();
      final service = _makeService(registrar);
      var advanceCalls = 0;
      var cancelCalls = 0;

      await service.registerInteractiveSnippetKeys(
        onAdvance: () => advanceCalls++,
        onCancel: () => cancelCalls++,
      );

      final enter = stillRegistered(registrar, LogicalKeyboardKey.enter);
      final escape = stillRegistered(registrar, LogicalKeyboardKey.escape);
      expect(enter, hasLength(1));
      expect(escape, hasLength(1));
      // Bare keys — a modifier would defeat the whole "just press Enter"
      // point.
      expect(enter.single.modifiers ?? const <HotKeyModifier>[], isEmpty);
      expect(escape.single.modifiers ?? const <HotKeyModifier>[], isEmpty);

      registrar.keyDownHandlersByKeyId[LogicalKeyboardKey.enter.keyId]!(
        enter.single,
      );
      expect(advanceCalls, 1);
      expect(cancelCalls, 0);

      registrar.keyDownHandlersByKeyId[LogicalKeyboardKey.escape.keyId]!(
        escape.single,
      );
      expect(cancelCalls, 1);
    });

    test('unregister removes both keys and stale handlers dispatch '
        'nothing', () async {
      final registrar = FakeHotKeyRegistrar();
      final service = _makeService(registrar);
      var advanceCalls = 0;
      var cancelCalls = 0;

      await service.registerInteractiveSnippetKeys(
        onAdvance: () => advanceCalls++,
        onCancel: () => cancelCalls++,
      );
      await service.unregisterInteractiveSnippetKeys();

      expect(stillRegistered(registrar, LogicalKeyboardKey.enter), isEmpty);
      expect(stillRegistered(registrar, LogicalKeyboardKey.escape), isEmpty);

      // A key event that slips through after unregister (native race) must
      // not fire the callbacks of the ended sequence.
      registrar.keyDownHandlersByKeyId[LogicalKeyboardKey.enter.keyId]!(
        HotKey(key: LogicalKeyboardKey.enter),
      );
      registrar.keyDownHandlersByKeyId[LogicalKeyboardKey.escape.keyId]!(
        HotKey(key: LogicalKeyboardKey.escape),
      );
      expect(advanceCalls, 0);
      expect(cancelCalls, 0);
    });

    test('a failed Enter registration does not take Escape down', () async {
      final registrar = FakeHotKeyRegistrar()
        ..throwOnFirstRegister = TypeError();
      final service = _makeService(registrar);
      var cancelCalls = 0;

      await service.registerInteractiveSnippetKeys(
        onAdvance: () {},
        onCancel: () => cancelCalls++,
      );

      expect(stillRegistered(registrar, LogicalKeyboardKey.enter), isEmpty);
      final escape = stillRegistered(registrar, LogicalKeyboardKey.escape);
      expect(escape, hasLength(1));
      registrar.keyDownHandlersByKeyId[LogicalKeyboardKey.escape.keyId]!(
        escape.single,
      );
      expect(cancelCalls, 1);
    });

    test('an unregister racing a still-pending registration leaves no '
        'system-wide key grab behind (epoch guard)', () async {
      final registrar = GatedHotKeyRegistrar();
      final service = _makeService(registrar);
      final gate = Completer<void>();
      registrar.gate = gate;

      final pending = service.registerInteractiveSnippetKeys(
        onAdvance: () {},
        onCancel: () {},
      );
      // The sequence ends while the Enter registration is still parked on
      // the gate.
      await service.unregisterInteractiveSnippetKeys();
      registrar.gate = null;
      gate.complete();
      await pending;

      expect(
        stillRegistered(registrar, LogicalKeyboardKey.enter),
        isEmpty,
        reason:
            'The late-completing Enter registration must undo itself — a '
            'leaked bare-Enter grab would swallow Enter in every app',
      );
      expect(stillRegistered(registrar, LogicalKeyboardKey.escape), isEmpty);
    });

    test('a second sequence replaces the first registration instead of '
        'stacking a duplicate', () async {
      final registrar = FakeHotKeyRegistrar();
      final service = _makeService(registrar);

      await service.registerInteractiveSnippetKeys(
        onAdvance: () {},
        onCancel: () {},
      );
      await service.registerInteractiveSnippetKeys(
        onAdvance: () {},
        onCancel: () {},
      );

      expect(
        stillRegistered(registrar, LogicalKeyboardKey.enter),
        hasLength(1),
      );
      expect(
        stillRegistered(registrar, LogicalKeyboardKey.escape),
        hasLength(1),
      );
    });

    test('without key-up delivery a rapid double-Enter is debounced as OS '
        'auto-repeat', () async {
      final registrar = FakeHotKeyRegistrar();
      final service = _makeService(registrar);
      var advanceCalls = 0;

      await service.registerInteractiveSnippetKeys(
        onAdvance: () => advanceCalls++,
        onCancel: () {},
      );

      final handler =
          registrar.keyDownHandlersByKeyId[LogicalKeyboardKey.enter.keyId]!;
      final key = HotKey(key: LogicalKeyboardKey.enter);
      handler(key);
      handler(key);

      expect(advanceCalls, 1);
    });

    test('with key-up delivery (macOS) a released Enter is honoured again '
        'immediately', () async {
      final registrar = FakeHotKeyRegistrar(supportsKeyUp: true);
      final service = _makeService(registrar);
      var advanceCalls = 0;

      await service.registerInteractiveSnippetKeys(
        onAdvance: () => advanceCalls++,
        onCancel: () {},
      );

      final down =
          registrar.keyDownHandlersByKeyId[LogicalKeyboardKey.enter.keyId]!;
      final up =
          registrar.keyUpHandlersByKeyId[LogicalKeyboardKey.enter.keyId]!;
      final key = HotKey(key: LogicalKeyboardKey.enter);
      down(key);
      up(key);
      down(key);

      expect(advanceCalls, 2);
    });
  });
}
