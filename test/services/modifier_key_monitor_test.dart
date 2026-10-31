/// Unit tests for the modifier-only hotkey observer (pure mapping plus the
/// macOS channel contract). No platform code runs here; the native hosts are
/// checked on the Mac by hand (see the report).
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/keyboard_up_monitor.dart';
import 'package:whispaste/services/modifier_key_monitor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.whispaste.modifier_monitor');
  late List<MethodCall> calls;
  late bool listenAccess;

  setUp(() {
    calls = [];
    listenAccess = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'status':
              return {'listenAccess': listenAccess};
            case 'requestListenAccess':
              return listenAccess;
            case 'start':
              if (!listenAccess) {
                throw PlatformException(code: 'UNSUPPORTED');
              }
              return true;
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('shared names', () {
    test('Fn is offered on macOS only', () {
      expect(modifierHotkeySupported(ModifierHotkey.fn, isMacOS: true), isTrue);
      expect(
        modifierHotkeySupported(ModifierHotkey.fn, isMacOS: false),
        isFalse,
      );
    });

    test('right Control, Alt and Meta are offered everywhere', () {
      for (final key in [
        ModifierHotkey.rightControl,
        ModifierHotkey.rightAlt,
        ModifierHotkey.rightMeta,
      ]) {
        expect(modifierHotkeySupported(key, isMacOS: false), isTrue);
        expect(modifierHotkeySupported(key, isMacOS: true), isTrue);
      }
    });

    test('native method names map to inputs, unknown names to null', () {
      expect(modifierInputForNativeCall('onModifierDown'), ModifierInput.down);
      expect(modifierInputForNativeCall('onModifierUp'), ModifierInput.up);
      expect(modifierInputForNativeCall('onOtherKey'), ModifierInput.other);
      expect(modifierInputForNativeCall('onKeyUp'), isNull);
    });
  });

  group('Windows and Linux routing', () {
    test('modifier inputs from the keyboard host reach the sink', () async {
      final monitor = ChannelKeyboardUpMonitor(isWindows: true, isLinux: false);
      final seen = <ModifierInput>[];
      monitor.onModifierInput = seen.add;
      const codec = StandardMethodCodec();
      for (final method in ['onModifierDown', 'onModifierUp', 'onOtherKey']) {
        await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .handlePlatformMessage(
              'com.whispaste.keyboard_monitor',
              codec.encodeMethodCall(MethodCall(method)),
              (_) {},
            );
      }
      expect(seen, [ModifierInput.down, ModifierInput.up, ModifierInput.other]);
    });

    test('Linux X11 watch makes the key-up capability known', () async {
      final native = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.whispaste.keyboard_monitor'),
            (call) async {
              native.add(call.method);
              return call.method == 'watchModifier' ? true : null;
            },
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('com.whispaste.keyboard_monitor'),
              null,
            ),
      );
      final monitor = ChannelKeyboardUpMonitor(isWindows: false, isLinux: true);
      expect(monitor.supportsKeyUp, isFalse);
      expect(await monitor.watchModifier(ModifierHotkey.rightControl), isTrue);
      expect(monitor.supportsKeyUp, isTrue);
    });

    test(
      'stop reaches the Linux host even without key-up capability',
      () async {
        final native = <String>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('com.whispaste.keyboard_monitor'),
              (call) async {
                native.add(call.method);
                return null;
              },
            );
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(
                const MethodChannel('com.whispaste.keyboard_monitor'),
                null,
              ),
        );
        final monitor = ChannelKeyboardUpMonitor(
          isWindows: false,
          isLinux: true,
        );
        expect(monitor.supportsKeyUp, isFalse);
        await monitor.stop();
        expect(native, contains('stop'));
      },
    );

    test('Fn cannot be watched off macOS', () async {
      final monitor = ChannelKeyboardUpMonitor(isWindows: true, isLinux: false);
      expect(await monitor.watchModifier(ModifierHotkey.fn), isFalse);
    });
  });

  group('macOS channel', () {
    test('start sends the shared key name and reports support', () async {
      final monitor = ModifierKeyMonitor(isMacOS: true, channel: channel);
      final ok = await monitor.start(ModifierHotkey.rightAlt);
      expect(ok, isTrue);
      final start = calls.singleWhere((c) => c.method == 'start');
      expect(start.arguments, {'key': 'rightAlt'});
    });

    test('without Input Monitoring it reports unsupported, no start', () async {
      listenAccess = false;
      final monitor = ModifierKeyMonitor(isMacOS: true, channel: channel);
      expect(await monitor.start(ModifierHotkey.rightControl), isFalse);
      expect(calls.where((c) => c.method == 'start'), isEmpty);
    });

    test(
      'requestAccess asks the native prompt and returns the answer',
      () async {
        final monitor = ModifierKeyMonitor(isMacOS: true, channel: channel);
        listenAccess = false;
        expect(await monitor.requestAccess(), isFalse);
        expect(calls.map((c) => c.method), contains('requestListenAccess'));
        expect(
          calls.where((c) => c.method == 'start'),
          isEmpty,
          reason: 'requesting access must not start observing',
        );
      },
    );

    test('native events reach the sink as down, up and other', () {
      final monitor = ModifierKeyMonitor(isMacOS: true, channel: channel);
      final seen = <ModifierInput>[];
      monitor.onInput = seen.add;
      monitor.handleNativeCall(const MethodCall('event', {'type': 'down'}));
      monitor.handleNativeCall(const MethodCall('event', {'type': 'up'}));
      monitor.handleNativeCall(const MethodCall('event', {'type': 'other'}));
      expect(seen, [ModifierInput.down, ModifierInput.up, ModifierInput.other]);
    });

    test(
      'a second instance (the permission flow) does not take over the events',
      () async {
        final observer = ModifierKeyMonitor(isMacOS: true, channel: channel);
        final seen = <ModifierInput>[];
        observer.onInput = seen.add;
        expect(await observer.start(ModifierHotkey.rightAlt), isTrue);

        // applyModifierOnlyHotkey creates its own instance to ask for access.
        final flow = ModifierKeyMonitor(isMacOS: true, channel: channel);
        await flow.requestAccess();

        const codec = StandardMethodCodec();
        await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .handlePlatformMessage(
              'com.whispaste.modifier_monitor',
              codec.encodeMethodCall(
                const MethodCall('event', {'type': 'down'}),
              ),
              (_) {},
            );
        expect(seen, [ModifierInput.down]);
      },
    );

    test('stop tells the host to stop observing', () async {
      final monitor = ModifierKeyMonitor(isMacOS: true, channel: channel);
      await monitor.stop();
      expect(calls.map((c) => c.method), contains('stop'));
    });
  });
}
