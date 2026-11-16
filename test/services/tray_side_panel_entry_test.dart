/// UIA-SHL-09: the side panel has a keyboard path through the tray menu.
/// The entry appears only while the panel is enabled, and clicking it opens
/// the panel without bringing the main window forward.
library;

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:whispaste/services/tray_service.dart';
import 'package:whispaste/services/window_activation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('tray_manager');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('the entry is hidden until the side panel is enabled', () async {
    final menus = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'setContextMenu') {
            menus.add(jsonEncode(call.arguments));
          }
          return null;
        });

    final container = ProviderContainer(
      overrides: [windowActivatorProvider.overrideWithValue(() async {})],
    );
    addTearDown(container.dispose);

    final tray = container.read(trayServiceProvider.notifier);
    await tray.initDone;
    expect(menus.last, isNot(contains('"key":"side_panel"')));

    tray.setSidePanelAvailable(true);
    await Future<void>.delayed(Duration.zero);
    expect(menus.last, contains('"key":"side_panel"'));
    expect(menus.last, contains('Open quick-paste panel'));

    tray.setSidePanelAvailable(false);
    await Future<void>.delayed(Duration.zero);
    expect(menus.last, isNot(contains('"key":"side_panel"')));
  });

  test('before the tray is set up, the flag waits for init', () async {
    final calls = <String>[];
    final menus = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          if (call.method == 'setContextMenu') {
            menus.add(jsonEncode(call.arguments));
          }
          return null;
        });

    // A tray that never initialises (tests, or a platform without one) must
    // not touch the plugin.
    final idle = ProviderContainer(
      overrides: [trayServiceProvider.overrideWith(_IdleTrayService.new)],
    );
    addTearDown(idle.dispose);
    idle.read(trayServiceProvider.notifier).setSidePanelAvailable(true);
    await Future<void>.delayed(Duration.zero);
    expect(calls, isEmpty);

    // Set while init is still running: the menu init builds has the entry.
    final container = ProviderContainer(
      overrides: [windowActivatorProvider.overrideWithValue(() async {})],
    );
    addTearDown(container.dispose);
    final tray = container.read(trayServiceProvider.notifier);
    tray.setSidePanelAvailable(true);
    await tray.initDone;
    await Future<void>.delayed(Duration.zero);
    expect(menus.last, contains('"key":"side_panel"'));
  });

  test(
    'clicking the entry opens the panel and does not show the window',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => null);

      var shown = 0;
      final container = ProviderContainer(
        overrides: [
          windowActivatorProvider.overrideWithValue(() async {
            shown++;
          }),
        ],
      );
      addTearDown(container.dispose);

      final tray = container.read(trayServiceProvider.notifier);
      await tray.initDone;
      var opened = 0;
      tray.onOpenSidePanel = () => opened++;

      tray.onTrayMenuItemClick(
        MenuItem(key: 'side_panel', label: 'Open quick-paste panel'),
      );
      await Future<void>.delayed(Duration.zero);

      expect(opened, 1);
      expect(shown, 0, reason: 'the panel is its own window');
    },
  );
}

class _IdleTrayService extends TrayService {
  @override
  void build() {}
}
