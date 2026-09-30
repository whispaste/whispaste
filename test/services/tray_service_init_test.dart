/// Regression test for the Linux tray-icon-goes-inert bug: `tray_manager`'s
/// Linux native plugin only implements destroy/setIcon/setTitle/
/// setContextMenu — `setToolTip` throws [MissingPluginException] there. That
/// call used to sit unguarded between `setIcon` and `addListener` inside a
/// single try block, so the exception aborted the rest of `_init()`: the
/// icon appeared (setIcon had already run) but no listener was ever attached
/// and no context menu was ever built, leaving the icon visible but inert to
/// both left- and right-click.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/tray_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('tray_manager');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('tray finishes initializing (listener attached, menu built) even when '
      'the platform plugin has no setToolTip implementation', () async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          if (call.method == 'setToolTip') {
            throw MissingPluginException(
              'No implementation found for method setToolTip on channel '
              'tray_manager',
            );
          }
          return null;
        });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    final tray = container.read(trayServiceProvider.notifier);
    // build() schedules _init() via Future.microtask; _init() awaits real
    // asset and file I/O before touching the channel. Await its completion:
    // a fixed pumpEventQueue() lost that race on a loaded machine.
    await tray.initDone;

    expect(
      tray.isInitialized,
      isTrue,
      reason:
          'a platform that cannot set a tooltip must not block listener '
          'and menu setup. calls so far: $calls',
    );
    expect(calls, contains('setIcon'));
    expect(calls, contains('setToolTip'));
    expect(calls, contains('setContextMenu'));
  });

  // Regression test for a flake: this file used to wait for the tray setup
  // with a fixed pumpEventQueue(), which a loaded machine outran (setup
  // does real asset/file I/O) — the test then saw "calls so far: []" and
  // its still-running setIcon leaked into the next test. 50ms of extra
  // asset latency reproduced that deterministically; initDone must cover it.
  test(
    'initDone covers the whole tray setup, even with slow asset I/O',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMessageHandler('flutter/assets', (message) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final bytes = File('assets/icons/logo-dark.png').readAsBytesSync();
        return ByteData.sublistView(bytes);
      });
      addTearDown(
        () => messenger.setMockMessageHandler('flutter/assets', null),
      );

      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return null;
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final tray = container.read(trayServiceProvider.notifier);
      await tray.initDone;

      expect(tray.isInitialized, isTrue, reason: 'calls so far: $calls');
      expect(calls, contains('setContextMenu'));
    },
  );

  // Regression test for the macOS "tray icon never appears / close keeps the
  // Dock icon" bug (Sentry FLUTTER_WHISPASTE-DT): on macOS `tray_manager`
  // loads the icon through `rootBundle.load(iconPath)`, i.e. it expects an
  // asset key, not a file path. An absolute bundle path only resolved by
  // accident, and broke as soon as the bundle path contained a character
  // that `rootBundle` URI-encodes (e.g. "/Applications/WhisPaste 2.app") —
  // the resulting FlutterError aborted `_init()` before `_initialized` was
  // set, so close-to-tray never switched the app to accessory mode.
  test(
    'macOS: tray initializes by handing tray_manager an asset key',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      // Resolve asset keys only, like the engine's bundle-rooted asset manager
      // does in a real app — the test harness would otherwise happily read an
      // absolute file path and hide the bug.
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMessageHandler('flutter/assets', (message) async {
        final key = utf8.decode(message!.buffer.asUint8List());
        if (key != 'assets/icons/logo-dark.png') return null;
        final bytes = File(key).readAsBytesSync();
        return ByteData.sublistView(bytes);
      });
      addTearDown(
        () => messenger.setMockMessageHandler('flutter/assets', null),
      );

      final setIconArgs = <Map<Object?, Object?>>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'setIcon') {
              setIconArgs.add(call.arguments as Map<Object?, Object?>);
            }
            return null;
          });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final tray = container.read(trayServiceProvider.notifier);
      await tray.initDone;

      expect(tray.isInitialized, isTrue);
      expect(setIconArgs, hasLength(1));
      expect(setIconArgs.single['base64Icon'], isA<String>());
    },
  );
}
