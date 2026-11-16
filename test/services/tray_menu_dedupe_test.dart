/// GH #159 / #83: a recording updates its state many times a second (input
/// level, elapsed time). The tray menu must only reach the platform when
/// what it shows changes; tray_manager's Linux plugin leaks a GtkMenu per
/// setContextMenu call.
library;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/services/tray_service.dart';

class _Settings extends SettingsNotifier {
  @override
  Future<AppSettings> build() async =>
      const AppSettings(interface_: InterfaceSettings(locale: 'en'));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('tray_manager');
  late int menus;
  late int toolTips;

  setUp(() {
    menus = 0;
    toolTips = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'setContextMenu') menus++;
          if (call.method == 'setToolTip') toolTips++;
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<TrayService> startedTray() async {
    final container = ProviderContainer(
      overrides: [settingsProvider.overrideWith(_Settings.new)],
    );
    addTearDown(container.dispose);
    await container.read(settingsProvider.future);
    final tray = container.read(trayServiceProvider.notifier);
    await tray.initDone;
    await pumpEventQueue();
    return tray;
  }

  test('a tooltip the platform refuses is contained, not an unhandled async '
      'error (core review L-16 F16-1)', () async {
    final tray = await startedTray();
    var refused = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'setToolTip') {
            refused++;
            throw MissingPluginException('setToolTip');
          }
          return null;
        });
    // Both calls are fire-and-forget in the tray service; a refused tooltip
    // must end in a log line, not in an error no caller awaits.
    tray.setActionNeeded(label: 'Paste', tooltip: 'Paste needs a permission');
    tray.clearActionNeeded();
    await pumpEventQueue();

    // A platform without a tooltip (Linux) is not asked again on every
    // rebuild while the tooltip stays the same.
    // The recording phase leads the tooltip (#137), so entering it is one
    // legitimate change; only the updates after it must not ask again.
    tray.updateRecordingState(
      const RecordingState(phase: RecordingPhase.recording),
    );
    await pumpEventQueue();
    final refusedBefore = refused;
    for (var i = 1; i <= 10; i++) {
      tray.updateRecordingState(
        RecordingState(phase: RecordingPhase.recording, audioLevel: i / 10),
      );
    }
    await pumpEventQueue();
    tray.updateRecordingState(
      const RecordingState(phase: RecordingPhase.recording, audioLevel: 0.5),
    );
    await pumpEventQueue();
    expect(refused, refusedBefore);
  });

  test('level and elapsed time alone send no menu; a phase change sends '
      'exactly one', () async {
    final tray = await startedTray();
    tray.updateRecordingState(
      const RecordingState(phase: RecordingPhase.recording),
    );
    await pumpEventQueue();
    final menusBefore = menus;
    final toolTipsBefore = toolTips;

    for (var i = 1; i <= 10; i++) {
      tray.updateRecordingState(
        RecordingState(
          phase: RecordingPhase.recording,
          audioLevel: i / 10,
          elapsed: Duration(milliseconds: 100 * i),
        ),
      );
    }
    await pumpEventQueue();
    expect(menus, menusBefore, reason: 'the menu content did not change');
    expect(toolTips, toolTipsBefore, reason: 'the tooltip did not change');

    tray.updateRecordingState(const RecordingState());
    await pumpEventQueue();
    expect(menus, menusBefore + 1);
  });

  test('menu content ignores the item IDs menu_base assigns', () {
    Menu build() => Menu(
      items: [
        MenuItem(key: 'a', label: 'A'),
        MenuItem.submenu(
          key: 'b',
          label: 'B',
          submenu: Menu(
            items: [MenuItem(key: 'c', label: 'C')],
          ),
        ),
      ],
    );
    expect(trayMenuContent(build()), trayMenuContent(build()));
    expect(
      trayMenuContent(build()),
      isNot(
        trayMenuContent(
          Menu(
            items: [MenuItem(key: 'a', label: 'A2')],
          ),
        ),
      ),
    );
  });
}
