/// Tests for the modifier-only global hotkey routing in [HotkeyService].
///
/// The native observer is replaced by [FakeModifierKeyMonitor]; the combo
/// registrar is [FakeHotKeyRegistrar] so no platform channel is touched.
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import 'package:whispaste/services/hotkey_service.dart';
import 'package:whispaste/services/keyboard_up_monitor.dart';
import 'package:whispaste/services/modifier_key_monitor.dart';

class FakeHotKeyRegistrar implements HotKeyRegistrar {
  final List<HotKey> registered = [];

  @override
  bool get supportsKeyUp => false;

  @override
  Future<void> register(
    HotKey hotKey, {
    HotKeyHandler? keyDownHandler,
    HotKeyHandler? keyUpHandler,
  }) async {
    registered.add(hotKey);
  }

  @override
  Future<void> unregister(HotKey hotKey) async {
    registered.removeWhere((k) => k.identifier == hotKey.identifier);
  }
}

class FakeModifierKeyMonitor implements ModifierKeyMonitor {
  FakeModifierKeyMonitor({this.startResult = true});

  bool startResult;
  final List<ModifierHotkey> started = [];
  int stopCount = 0;

  @override
  ValueChanged<ModifierInput>? onInput;

  @override
  Future<bool> requestAccess() async => true;

  @override
  Future<bool> start(ModifierHotkey key) async {
    started.add(key);
    return startResult;
  }

  @override
  Future<void> stop() async => stopCount++;

  @override
  Future<void> handleNativeCall(MethodCall call) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeHotKeyRegistrar registrar;
  late FakeModifierKeyMonitor monitor;
  late HotkeyService service;
  late int pressed;
  late int released;
  late int otherKey;

  setUp(() {
    registrar = FakeHotKeyRegistrar();
    monitor = FakeModifierKeyMonitor();
    service = HotkeyService()
      ..injectRegistrar(registrar)
      ..injectMonitor(NoopKeyboardUpMonitor())
      ..injectModifierMonitor(monitor);
    pressed = 0;
    released = 0;
    otherKey = 0;
    service.onHotkeyPressed = () {
      pressed++;
    };
    service.onHotkeyReleased = () {
      released++;
    };
    service.onModifierOtherKey = () {
      otherKey++;
    };
  });

  test('starts the observer and registers no key combination', () async {
    final started = await service.registerModifierOnly(
      ModifierHotkey.rightControl,
    );

    expect(started, isTrue);
    expect(monitor.started, [ModifierHotkey.rightControl]);
    expect(registrar.registered, isEmpty);
  });

  test(
    'a modifier press starts and its release stops the global action',
    () async {
      await service.registerModifierOnly(ModifierHotkey.rightAlt);

      monitor.onInput!(ModifierInput.down);
      monitor.onInput!(ModifierInput.up);

      expect(pressed, 1);
      expect(released, 1);
    },
  );

  test(
    'another key while the modifier is held is routed as other, not as a press',
    () async {
      await service.registerModifierOnly(ModifierHotkey.rightMeta);

      monitor.onInput!(ModifierInput.down);
      monitor.onInput!(ModifierInput.other);

      expect(pressed, 1);
      expect(otherKey, 1);
      expect(released, 0);
    },
  );

  test(
    'reports false and keeps the combination when the platform cannot observe the key',
    () async {
      monitor.startResult = false;

      final started = await service.registerModifierOnly(ModifierHotkey.fn);

      expect(started, isFalse);
      expect(registrar.registered, isEmpty);
    },
  );

  test('switching back to a combination stops the modifier observer', () async {
    await service.registerModifierOnly(ModifierHotkey.rightControl);

    await service.updateHotkey(key: LogicalKeyboardKey.keyR);

    expect(monitor.stopCount, greaterThanOrEqualTo(1));
  });
}
