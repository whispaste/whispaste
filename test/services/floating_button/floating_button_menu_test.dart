/// #393: the floating button's right-click menu is the tray's command tree.
/// The button sends the tree the tray built and hands every chosen id back to
/// the tray's command handler; copying a recent recording still answers on
/// the button (UIA-SHL-11).
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/overlay_customization.dart';
import 'package:whispaste/services/app_commands/app_command.dart';
import 'package:whispaste/services/app_commands/tray_command_catalog.dart';
import 'package:whispaste/services/floating_button/floating_button_controller.dart';
import 'package:whispaste/services/floating_button/floating_button_events.dart';
import 'package:whispaste/services/floating_button/floating_button_service.dart';
import 'package:whispaste/services/tray_service.dart';

class _Controller implements FloatingButtonController {
  final bus = StreamController<FloatingButtonEvent>.broadcast();
  final states = <FloatingButtonVisualState>[];
  List<Map<String, Object?>> menu = const [];

  @override
  Stream<FloatingButtonEvent> get events => bus.stream;

  @override
  Future<void> setContextMenuItems(
    List<Map<String, Object?>> items, {
    String appearance = 'system',
  }) async => menu = items;

  @override
  Future<void> dispose() => bus.close();

  @override
  Future<void> show({double x = 200, double y = 200, int size = 56}) async {}

  @override
  Future<void> hide() async {}

  @override
  Future<void> setState(FloatingButtonVisualState state) async =>
      states.add(state);

  @override
  Future<void> setPosition(double x, double y) async {}

  @override
  Future<void> setSize(int size) async {}

  @override
  Future<void> setTheme({
    required String background,
    required String wave,
    FloatingButtonLook look = FloatingButtonLook.defaults,
  }) async {}

  @override
  Future<({double x, double y})?> getPosition() async => null;
}

class _Service extends FloatingButtonService {
  _Service(this._controller);
  final _Controller _controller;

  @override
  FloatingButtonController? createController() => _controller;
}

class _Tray extends TrayService {
  final activated = <String>[];
  final copied = <String>[];
  Object? copyError;

  @override
  void build() {}

  @override
  void activateCommand(String key) => activated.add(key);

  @override
  Future<void> copyRecentRecording(String recordingId) async {
    final error = copyError;
    if (error != null) throw error;
    copied.add(recordingId);
  }
}

const _tree = [
  AppCommand(id: TrayCommandIds.toggleRecording, labelKey: 'trayStart'),
  AppCommand(
    id: TrayCommandIds.language,
    labelKey: 'trayLanguage',
    children: [AppCommand(id: 'lang:de', labelKey: 'Deutsch', checked: true)],
  ),
];

Future<({_Controller controller, _Tray tray, ProviderContainer container})>
_start() async {
  final controller = _Controller();
  final tray = _Tray();
  final container = ProviderContainer(
    overrides: [
      floatingButtonServiceProvider.overrideWith(() => _Service(controller)),
      trayServiceProvider.overrideWith(() => tray),
    ],
  );
  addTearDown(() async {
    container.dispose();
    await controller.dispose();
  });
  container.read(trayMenuSnapshotProvider.notifier).publish((
    commands: _tree,
    labels: const {'trayStart': 'Start recording', 'trayLanguage': 'Language'},
  ));
  container.listen(floatingButtonServiceProvider, (_, _) {});
  await Future<void>.delayed(Duration.zero);
  return (controller: controller, tray: tray, container: container);
}

Future<void> _choose(_Controller c, String id) async {
  c.bus.add(FloatingButtonContextMenuSelected(id));
  await pumpEventQueue();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the button shows the tray tree with its labels and choices', () async {
    final (:controller, tray: _, container: _) = await _start();

    expect(controller.menu.first['id'], TrayCommandIds.toggleRecording);
    expect(controller.menu.first['label'], 'Start recording');
    final language = controller.menu[1];
    expect(language['label'], 'Language');
    final children = language['children']! as List<Map<String, Object?>>;
    expect(children.single['checked'], isTrue);
  });

  test('a rebuilt tray tree reaches the button', () async {
    final (:controller, tray: _, :container) = await _start();

    container.read(trayMenuSnapshotProvider.notifier).publish((
      commands: const [AppCommand(id: TrayCommandIds.quit, labelKey: 'q')],
      labels: const {'q': 'Quit'},
    ));
    await Future<void>.delayed(Duration.zero);

    expect(controller.menu.single['label'], 'Quit');
  });

  test('a chosen entry runs through the tray command handler', () async {
    final (:controller, :tray, container: _) = await _start();

    await _choose(controller, 'lang:de');

    expect(tray.activated, ['lang:de']);
  });

  test('copying a recent recording briefly shows done on the button', () async {
    final (:controller, :tray, container: _) = await _start();
    controller.states.clear();

    await _choose(controller, trayRecentKey('entry-1'));

    expect(tray.copied, ['entry-1']);
    expect(tray.activated, isEmpty);
    expect(controller.states, [FloatingButtonVisualState.done]);
  });

  test('a failed copy shows error on the button, not silence', () async {
    final (:controller, :tray, container: _) = await _start();
    tray.copyError = PlatformException(code: 'clipboard-denied');
    controller.states.clear();

    await _choose(controller, trayRecentKey('entry-1'));

    expect(controller.states, [FloatingButtonVisualState.error]);
  });
}
