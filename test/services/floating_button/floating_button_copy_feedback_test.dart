/// UIA-SHL-11: copying a recent transcription from the floating button's menu
/// answers on the button, both on success ("done") and on failure ("error").
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/data/history_providers.dart';
import 'package:whispaste/services/floating_button/floating_button_controller.dart';
import 'package:whispaste/services/floating_button/floating_button_events.dart';
import 'package:whispaste/services/floating_button/floating_button_service.dart';
import 'package:whispaste/core/theme/overlay_customization.dart';

class _StateRecordingController implements FloatingButtonController {
  final _events = StreamController<FloatingButtonEvent>.broadcast();
  final states = <FloatingButtonVisualState>[];

  @override
  Stream<FloatingButtonEvent> get events => _events.stream;

  @override
  Future<void> setContextMenuItems(List<Map<String, String>> items) async {}

  @override
  Future<void> dispose() => _events.close();

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

class _TestableService extends FloatingButtonService {
  _TestableService(this._fake);
  final _StateRecordingController _fake;

  @override
  FloatingButtonController? createController() => _fake;
}

final _entry = HistoryEntry(
  id: 'entry-1',
  content: 'Copy me',
  title: '',
  timestamp: DateTime(2026, 1, 1, 12),
  durationSec: 3.0,
  processingDurationSec: 1.0,
  language: 'en',
  languageHint: '',
  tags: '[]',
  pinned: false,
  source: 'microphone',
  model: 'whisper-small',
  isLocal: true,
  costUsd: 0.0,
  archived: false,
  deletedAt: null,
  titleEdited: false,
  colorSlot: 0,
);

/// Runs "copy entry-1" from the floating button's menu with the given
/// clipboard behaviour and returns the states the button showed.
Future<List<FloatingButtonVisualState>> _copyFromMenu({
  required Future<Object?> Function(MethodCall call) clipboardHandler,
}) async {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, clipboardHandler);
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );

  final fake = _StateRecordingController();
  final container = ProviderContainer(
    overrides: [
      floatingButtonServiceProvider.overrideWith(() => _TestableService(fake)),
      historyEntriesProvider.overrideWith((ref) => Stream.value([_entry])),
    ],
  );
  addTearDown(() async {
    container.dispose();
    await fake.dispose();
  });
  container.listen(floatingButtonServiceProvider, (_, _) {});
  await container.read(historyEntriesProvider.future);
  await Future<void>.delayed(Duration.zero);
  fake.states.clear();

  fake._events.add(const FloatingButtonContextMenuSelected('entry-1'));
  await Future<void>.delayed(const Duration(milliseconds: 20));
  return List.of(fake.states);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a successful copy briefly shows done on the button', () async {
    final states = await _copyFromMenu(clipboardHandler: (_) async => null);
    expect(states, [FloatingButtonVisualState.done]);
  });

  test('a failed copy shows error on the button, not silence', () async {
    final states = await _copyFromMenu(
      clipboardHandler: (_) async =>
          throw PlatformException(code: 'clipboard-denied'),
    );
    expect(states, [FloatingButtonVisualState.error]);
  });
}
