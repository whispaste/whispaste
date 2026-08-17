/// Regression test for the Linux tray-icon-goes-inert bug: `tray_manager`'s
/// Linux native plugin only implements destroy/setIcon/setTitle/
/// setContextMenu — `setToolTip` throws [MissingPluginException] there. That
/// call used to sit unguarded between `setIcon` and `addListener` inside a
/// single try block, so the exception aborted the rest of `_init()`: the
/// icon appeared (setIcon had already run) but no listener was ever attached
/// and no context menu was ever built, leaving the icon visible but inert to
/// both left- and right-click.
library;

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
    // build() schedules _init() via Future.microtask; _init() itself
    // awaits real asset I/O (rootBundle.load) before touching the
    // channel — drain the whole event queue, not just one microtask turn.
    await pumpEventQueue();

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
}
