// The left click on the tray icon: panel when a shell exists and shows, native
// menu when it fails, window when there is no shell (Windows/Linux, slice 1).
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/audio_service.dart';
import 'package:whispaste/services/tray_panel/tray_panel_controller.dart';
import 'package:whispaste/services/tray_panel/tray_panel_protocol.dart';
import 'package:whispaste/services/tray_service.dart';
import 'package:whispaste/services/window_activation.dart';

class _FakePanel implements TrayPanelController {
  _FakePanel({this.shows = true});
  final bool shows;
  final shown = <TrayPanelContent>[];
  final controller = StreamController<TrayPanelEvent>.broadcast();

  @override
  Stream<TrayPanelEvent> get events => controller.stream;
  @override
  Future<bool> toggle(TrayPanelContent content) async {
    shown.add(content);
    return shows;
  }

  @override
  Future<void> update(TrayPanelContent content) async {}
  @override
  Future<void> hide() async {}
  @override
  Future<void> dispose() => controller.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const trayChannel = MethodChannel('tray_manager');
  final trayCalls = <String>[];

  /// Completes when the native menu pops up, so a test waits for that call
  /// itself instead of polling with fixed sleeps (#1491).
  late Completer<void> menuPoppedUp;

  setUp(() {
    trayCalls.clear();
    menuPoppedUp = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(trayChannel, (call) async {
          trayCalls.add(call.method);
          if (call.method == 'popUpContextMenu' && !menuPoppedUp.isCompleted) {
            menuPoppedUp.complete();
          }
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(trayChannel, null);
  });

  ProviderContainer containerWith(
    TrayPanelController? panel,
    List<String> log,
  ) {
    final c = ProviderContainer(
      overrides: [
        trayPanelControllerProvider.overrideWithValue(panel),
        audioInputDevicesProvider.overrideWith((ref) async => const <String>[]),
        windowActivatorProvider.overrideWithValue(
          () async => log.add('window'),
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test(
    'without a panel shell the click restores the window as before',
    () async {
      final log = <String>[];
      final c = containerWith(null, log);
      c.read(trayServiceProvider.notifier).onTrayIconMouseDown();
      await pumpEventQueue();
      expect(log, ['window']);
    },
  );

  test('a panel that shows replaces window and menu', () async {
    final log = <String>[];
    final panel = _FakePanel();
    final c = containerWith(panel, log);
    final tray = c.read(trayServiceProvider.notifier);
    await tray.initDone;
    tray.onTrayIconMouseDown();
    await pumpEventQueue();
    expect(log, isEmpty);
    expect(trayCalls, isNot(contains('popUpContextMenu')));
  });

  test('a panel that fails to show falls back to the native menu', () async {
    final log = <String>[];
    final panel = _FakePanel(shows: false);
    final c = containerWith(panel, log);
    final tray = c.read(trayServiceProvider.notifier);
    await tray.initDone;
    tray.onTrayIconMouseDown();
    // The menu path refreshes the microphone list first (up to 800 ms).
    await menuPoppedUp.future.timeout(
      const Duration(seconds: 3),
      onTimeout: () {},
    );
    expect(log, isEmpty);
    expect(trayCalls, contains('popUpContextMenu'));
  });
}
