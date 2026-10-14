/// Unit tests for [ChannelKeyboardUpMonitor]'s Linux path (ticket
/// handy-catchup/09): runtime capability probe, MissingPluginException
/// fallback, portal Activated/Deactivated → key-down/key-up mapping and the
/// XDG shortcut trigger derived from the hotkey.
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import 'package:whispaste/services/keyboard_up_monitor.dart';

const _channel = MethodChannel('com.whispaste.keyboard_monitor');

final _hotKey = HotKey(
  key: LogicalKeyboardKey.space,
  modifiers: [HotKeyModifier.control, HotKeyModifier.shift],
);

/// Delivers a native → Dart call on the monitor channel.
Future<void> _nativeCall(String method, [Object? arguments]) async {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  await messenger.handlePlatformMessage(
    _channel.name,
    _channel.codec.encodeMethodCall(MethodCall(method, arguments)),
    (_) {},
  );
}

void _mockNative(Future<Object?>? Function(MethodCall call) handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, handler);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => _mockNative((_) async => null));

  group('ChannelKeyboardUpMonitor — Linux capability probe', () {
    test('reports no key-up before the native probe ran', () {
      final monitor = ChannelKeyboardUpMonitor(isWindows: false, isLinux: true);

      expect(monitor.supportsKeyUp, isFalse);
      expect(monitor.experimental, isFalse);
    });

    test('X11 path available → key-up supported and experimental', () async {
      final calls = <MethodCall>[];
      _mockNative((call) async {
        calls.add(call);
        return {'x11': true, 'portal': false};
      });
      final monitor = ChannelKeyboardUpMonitor(isWindows: false, isLinux: true);

      await monitor.start(_hotKey);

      expect(monitor.supportsKeyUp, isTrue);
      expect(monitor.experimental, isTrue);
      expect(calls.single.method, 'start');
      expect(
        (calls.single.arguments as Map)['trigger'],
        'CTRL+SHIFT+space',
        reason: 'the portal binds the same combination as the X11 grab',
      );
    });

    test('portal path alone also enables key-up', () async {
      _mockNative((_) async => {'x11': false, 'portal': true});
      final monitor = ChannelKeyboardUpMonitor(isWindows: false, isLinux: true);

      await monitor.start(_hotKey);

      expect(monitor.supportsKeyUp, isTrue);
    });

    test('neither path → key-up stays unavailable', () async {
      _mockNative((_) async => {'x11': false, 'portal': false});
      final monitor = ChannelKeyboardUpMonitor(isWindows: false, isLinux: true);

      await monitor.start(_hotKey);

      expect(monitor.supportsKeyUp, isFalse);
      expect(monitor.experimental, isFalse);
    });

    test('MissingPluginException (older runner) → false, no throw', () async {
      _mockNative((_) async => throw MissingPluginException());
      final monitor = ChannelKeyboardUpMonitor(isWindows: false, isLinux: true);

      await monitor.start(_hotKey);

      expect(monitor.supportsKeyUp, isFalse);
    });

    test('unexpected reply shape → false', () async {
      _mockNative((_) async => true);
      final monitor = ChannelKeyboardUpMonitor(isWindows: false, isLinux: true);

      await monitor.start(_hotKey);

      expect(monitor.supportsKeyUp, isFalse);
    });

    test('native capability update (portal bind failed) is honoured', () async {
      _mockNative((_) async => {'x11': false, 'portal': true});
      final monitor = ChannelKeyboardUpMonitor(isWindows: false, isLinux: true);
      await monitor.start(_hotKey);

      await _nativeCall('onCapabilities', {'x11': false, 'portal': false});

      expect(monitor.supportsKeyUp, isFalse);
    });

    test('stop keeps the last known capability for the settings UI', () async {
      _mockNative((_) async => {'x11': true, 'portal': false});
      final monitor = ChannelKeyboardUpMonitor(isWindows: false, isLinux: true);
      await monitor.start(_hotKey);

      await monitor.stop();

      expect(monitor.supportsKeyUp, isTrue);
    });
  });

  group('ChannelKeyboardUpMonitor — native events', () {
    test('onKeyDown (portal Activated) reaches the key-down handler', () async {
      final monitor = ChannelKeyboardUpMonitor(isWindows: false, isLinux: true);
      var downs = 0;
      monitor.onKeyDown = () => downs++;

      await _nativeCall('onKeyDown');

      expect(downs, 1);
    });

    test('onKeyUp (portal Deactivated / X11 release) reaches the key-up '
        'handler', () async {
      final monitor = ChannelKeyboardUpMonitor(isWindows: false, isLinux: true);
      var ups = 0;
      monitor.onKeyUp = () => ups++;

      await _nativeCall('onKeyUp');

      expect(ups, 1);
    });
  });

  group('ChannelKeyboardUpMonitor — Windows unchanged', () {
    test('supports key-up without a probe and is not experimental', () {
      final monitor = ChannelKeyboardUpMonitor(isWindows: true, isLinux: false);

      expect(monitor.supportsKeyUp, isTrue);
      expect(monitor.experimental, isFalse);
    });

    test('a bool start reply does not disable Windows key-up', () async {
      _mockNative((_) async => false);
      final monitor = ChannelKeyboardUpMonitor(isWindows: true, isLinux: false);

      await monitor.start(_hotKey);

      expect(monitor.supportsKeyUp, isTrue);
    });
  });

  group('xdgShortcutTrigger', () {
    String? trigger(LogicalKeyboardKey key, [List<HotKeyModifier>? mods]) =>
        xdgShortcutTrigger(HotKey(key: key, modifiers: mods));

    test('letters and digits are lower-case keysyms', () {
      expect(trigger(LogicalKeyboardKey.keyD, [HotKeyModifier.alt]), 'ALT+d');
      expect(trigger(LogicalKeyboardKey.digit5), '5');
    });

    test('meta maps to LOGO, modifiers keep a stable order', () {
      expect(
        trigger(LogicalKeyboardKey.keyR, [
          HotKeyModifier.meta,
          HotKeyModifier.shift,
          HotKeyModifier.control,
        ]),
        'CTRL+SHIFT+LOGO+r',
      );
    });

    test('named keys use their X keysym', () {
      expect(trigger(LogicalKeyboardKey.f9), 'F9');
      expect(trigger(LogicalKeyboardKey.enter), 'Return');
      expect(trigger(LogicalKeyboardKey.pageUp), 'Page_Up');
    });

    test('unknown keys yield null (the portal dialog lets the user pick)', () {
      expect(trigger(LogicalKeyboardKey.mediaPlayPause), isNull);
    });
  });
}
