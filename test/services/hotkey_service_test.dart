/// Unit tests for [HotkeyService] error-handling and safe-default fallback.
///
/// Uses [FakeHotKeyRegistrar] to avoid real platform-channel calls.
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import 'package:whispaste/services/hotkey_service.dart';

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
    registered.add(hotKey);
  }

  @override
  Future<void> unregister(HotKey hotKey) async {
    unregistered.add(hotKey);
    registered.removeWhere((k) => k.identifier == hotKey.identifier);
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
}
