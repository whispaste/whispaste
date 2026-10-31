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
      monitor.onKeyUp = (_) => ups++;

      await _nativeCall('onKeyUp');

      expect(ups, 1);
    });

    test('onKeyUp reports the native press length, unknown when absent or '
        'malformed', () async {
      final monitor = ChannelKeyboardUpMonitor(isWindows: false, isLinux: true);
      final lengths = <Duration?>[];
      monitor.onKeyUp = lengths.add;

      await _nativeCall('onKeyUp', {'pressMs': 150});
      await _nativeCall('onKeyUp');
      await _nativeCall('onKeyUp', {'pressMs': 'soon'});

      expect(lengths, [const Duration(milliseconds: 150), null, null]);
    });
  });

  group('armRelease modifier mask (Windows, F35-5)', () {
    test('sends the hotkey modifiers as the native bit mask', () async {
      final calls = <MethodCall>[];
      _mockNative((call) async {
        calls.add(call);
        return null;
      });
      final monitor = ChannelKeyboardUpMonitor(isWindows: true, isLinux: false);

      await monitor.armRelease(
        modifiers: [HotKeyModifier.control, HotKeyModifier.alt],
      );

      final arm = calls.singleWhere((c) => c.method == 'armRelease');
      expect(arm.arguments, {'modifiers': 0x3});
    });

    test('an unmodified hotkey arms with an empty mask', () async {
      final calls = <MethodCall>[];
      _mockNative((call) async {
        calls.add(call);
        return null;
      });
      final monitor = ChannelKeyboardUpMonitor(isWindows: true, isLinux: false);

      await monitor.armRelease();

      final arm = calls.singleWhere((c) => c.method == 'armRelease');
      expect(arm.arguments, {'modifiers': 0});
    });

    test('each hotkey modifier maps to its own bit', () {
      expect(armedModifierMask([HotKeyModifier.control]), 0x1);
      expect(armedModifierMask([HotKeyModifier.alt]), 0x2);
      expect(armedModifierMask([HotKeyModifier.shift]), 0x4);
      expect(armedModifierMask([HotKeyModifier.meta]), 0x8);
      expect(armedModifierMask([HotKeyModifier.capsLock]), 0);
      expect(
        armedModifierMask([
          HotKeyModifier.control,
          HotKeyModifier.alt,
          HotKeyModifier.shift,
          HotKeyModifier.meta,
        ]),
        0xF,
      );
    });
  });

  group('waylandHotkeyBindingFrom (XP-2-06)', () {
    test('no Wayland session, old runner or odd reply → not applicable', () {
      expect(
        waylandHotkeyBindingFrom({'x11': true, 'portal': false}),
        WaylandHotkeyBinding.notApplicable,
      );
      expect(
        waylandHotkeyBindingFrom({'x11': true, 'wayland': false}),
        WaylandHotkeyBinding.notApplicable,
      );
      expect(
        waylandHotkeyBindingFrom(false),
        WaylandHotkeyBinding.notApplicable,
      );
    });

    test('portal found, binding not confirmed yet → pending', () {
      expect(
        waylandHotkeyBindingFrom({'wayland': true, 'portal': true}),
        WaylandHotkeyBinding.pending,
      );
    });

    test('bound wins', () {
      expect(
        waylandHotkeyBindingFrom({
          'wayland': true,
          'portal': true,
          'bound': true,
        }),
        WaylandHotkeyBinding.bound,
      );
    });

    test('each native reason maps to its own binding', () {
      Map<String, Object> failed(String reason) => {
        'wayland': true,
        'portal': false,
        'reason': reason,
      };
      expect(
        waylandHotkeyBindingFrom(failed('no-app-id')),
        WaylandHotkeyBinding.noAppId,
      );
      expect(
        waylandHotkeyBindingFrom(failed('unavailable')),
        WaylandHotkeyBinding.unavailable,
      );
      expect(
        waylandHotkeyBindingFrom(failed('declined')),
        WaylandHotkeyBinding.declined,
      );
    });

    test('Wayland without portal and without a reason → unavailable', () {
      expect(
        waylandHotkeyBindingFrom({'wayland': true, 'portal': false}),
        WaylandHotkeyBinding.unavailable,
      );
    });
  });

  group('ChannelKeyboardUpMonitor — Wayland binding', () {
    test('start passes the localized shortcut description', () async {
      final calls = <MethodCall>[];
      _mockNative((call) async {
        calls.add(call);
        return {'x11': false, 'portal': true, 'wayland': true};
      });
      final monitor = ChannelKeyboardUpMonitor(isWindows: false, isLinux: true);

      await monitor.start(_hotKey, description: 'WhisPaste-Diktat');

      expect(
        calls.single.arguments,
        containsPair('description', 'WhisPaste-Diktat'),
      );
      expect(monitor.waylandBinding, WaylandHotkeyBinding.pending);
    });

    test(
      'a later bound / failed push updates the binding and notifies',
      () async {
        _mockNative(
          (_) async => {'x11': false, 'portal': true, 'wayland': true},
        );
        final monitor = ChannelKeyboardUpMonitor(
          isWindows: false,
          isLinux: true,
        );
        var changes = 0;
        monitor.onWaylandBindingChanged = () => changes++;
        await monitor.start(_hotKey);
        expect(changes, 1);

        await _nativeCall('onCapabilities', {
          'x11': false,
          'portal': true,
          'wayland': true,
          'bound': true,
        });
        expect(monitor.waylandBinding, WaylandHotkeyBinding.bound);
        expect(monitor.supportsKeyUp, isTrue);

        await _nativeCall('onCapabilities', {
          'x11': false,
          'portal': false,
          'wayland': true,
          'reason': 'declined',
        });
        expect(monitor.waylandBinding, WaylandHotkeyBinding.declined);
        expect(changes, 3);
      },
    );

    test(
      'the trigger the desktop bound is read from the start reply',
      () async {
        _mockNative(
          (_) async => {
            'x11': false,
            'portal': true,
            'wayland': true,
            'bound': true,
            'triggerDescription': 'LOGO+space',
          },
        );
        final monitor = ChannelKeyboardUpMonitor(
          isWindows: false,
          isLinux: true,
        );
        await monitor.start(_hotKey);
        expect(monitor.waylandTrigger, 'LOGO+space');
      },
    );

    test(
      'a changed trigger is read and notifies, an equal one does not',
      () async {
        _mockNative(
          (_) async => {'x11': false, 'portal': true, 'wayland': true},
        );
        final monitor = ChannelKeyboardUpMonitor(
          isWindows: false,
          isLinux: true,
        );
        var changes = 0;
        monitor.onWaylandBindingChanged = () => changes++;
        await monitor.start(_hotKey);
        expect(monitor.waylandTrigger, isNull);

        await _nativeCall('onCapabilities', {
          'x11': false,
          'portal': true,
          'wayland': true,
          'bound': true,
          'triggerDescription': 'LOGO+space',
        });
        expect(monitor.waylandTrigger, 'LOGO+space');
        final afterBound = changes;

        await _nativeCall('onCapabilities', {
          'x11': false,
          'portal': true,
          'wayland': true,
          'bound': true,
          'triggerDescription': 'CTRL+d',
        });
        expect(monitor.waylandTrigger, 'CTRL+d');
        expect(changes, afterBound + 1);

        await _nativeCall('onCapabilities', {
          'x11': false,
          'portal': true,
          'wayland': true,
          'bound': true,
          'triggerDescription': 'CTRL+d',
        });
        expect(
          changes,
          afterBound + 1,
          reason: 'an unchanged trigger is silent',
        );
      },
    );

    test('an unchanged report does not notify again', () async {
      _mockNative((_) async => {'x11': true, 'portal': false});
      final monitor = ChannelKeyboardUpMonitor(isWindows: false, isLinux: true);
      var changes = 0;
      monitor.onWaylandBindingChanged = () => changes++;

      await monitor.start(_hotKey);

      expect(monitor.waylandBinding, WaylandHotkeyBinding.notApplicable);
      expect(changes, 0);
    });

    test('Windows and the no-op monitor are never Wayland', () async {
      _mockNative((_) async => null);
      final windows = ChannelKeyboardUpMonitor(isWindows: true, isLinux: false);
      await windows.start(_hotKey);
      expect(windows.waylandBinding, WaylandHotkeyBinding.notApplicable);
      expect(
        NoopKeyboardUpMonitor().waylandBinding,
        WaylandHotkeyBinding.notApplicable,
      );
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
