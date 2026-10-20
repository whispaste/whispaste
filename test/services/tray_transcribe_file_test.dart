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

  test('context menu offers "Transcribe file…" with a stable key', () async {
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

    expect(menus, isNotEmpty);
    expect(menus.last, contains('"key":"transcribe_file"'));
    expect(menus.last, contains('Transcribe file…'));
  });

  test(
    'clicking the entry shows the window and requests the file import',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => null);

      var shown = 0;
      var transcribeRequests = 0;
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
      tray.onTranscribeFile = () => transcribeRequests++;

      tray.onTrayMenuItemClick(
        MenuItem(key: 'transcribe_file', label: 'Transcribe file…'),
      );
      await Future<void>.delayed(Duration.zero);

      expect(shown, 1, reason: 'the window must come to the front');
      expect(transcribeRequests, 1);
    },
  );
}
