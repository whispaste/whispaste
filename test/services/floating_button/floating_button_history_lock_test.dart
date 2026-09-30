/// The floating button's right-click menu lists the most recent
/// transcriptions — while the history is PIN-locked it must not
/// (`.scratch/history-pin-lock/`).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/data/history_providers.dart';
import 'package:whispaste/features/history/data/history_lock.dart';
import 'package:whispaste/features/history/data/history_pin.dart';
import 'package:whispaste/services/floating_button/floating_button_controller.dart';
import 'package:whispaste/services/floating_button/floating_button_events.dart';
import 'package:whispaste/services/floating_button/floating_button_service.dart';

class _MenuRecordingController implements FloatingButtonController {
  final _events = StreamController<FloatingButtonEvent>.broadcast();
  List<Map<String, String>> lastMenu = const [];

  @override
  Stream<FloatingButtonEvent> get events => _events.stream;

  @override
  Future<void> setContextMenuItems(List<Map<String, String>> items) async =>
      lastMenu = items;

  @override
  Future<void> dispose() => _events.close();

  @override
  Future<void> show({double x = 200, double y = 200, int size = 56}) async {}

  @override
  Future<void> hide() async {}

  @override
  Future<void> setState(FloatingButtonVisualState state) async {}

  @override
  Future<void> setPosition(double x, double y) async {}

  @override
  Future<void> setSize(int size) async {}

  @override
  Future<({double x, double y})?> getPosition() async => null;
}

class _TestableService extends FloatingButtonService {
  _TestableService(this._fake);
  final _MenuRecordingController _fake;

  @override
  FloatingButtonController? createController() => _fake;
}

class _FakeSettingsNotifier extends SettingsNotifier {
  _FakeSettingsNotifier(this._settings);
  AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    _settings = updater(state.value ?? _settings);
    state = AsyncData(_settings);
  }
}

final _entry = HistoryEntry(
  id: 'entry-1',
  content: 'Secret dictation',
  title: '',
  timestamp: DateTime(2026, 1, 1, 12),
  durationSec: 30.0,
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  bool menuShowsEntry(_MenuRecordingController c) =>
      c.lastMenu.any((item) => item['id'] == _entry.id);

  test('recent transcriptions are withheld while PIN-locked', () async {
    final fake = _MenuRecordingController();
    final container = ProviderContainer(
      overrides: [
        floatingButtonServiceProvider.overrideWith(
          () => _TestableService(fake),
        ),
        settingsProvider.overrideWith(
          () => _FakeSettingsNotifier(
            AppSettings(
              history: HistorySettings(
                historyHideOnOpen: true,
                historyPin: hashHistoryPin('4711', iterations: 10),
              ),
            ),
          ),
        ),
        historyEntriesProvider.overrideWith((ref) => Stream.value([_entry])),
      ],
    );
    addTearDown(container.dispose);
    await container.read(settingsProvider.future);
    container.listen(floatingButtonServiceProvider, (_, _) {});
    await container.read(historyEntriesProvider.future);
    await Future<void>.delayed(Duration.zero);

    expect(menuShowsEntry(fake), isFalse);

    await container
        .read(historyRevealedProvider.notifier)
        .unlockWithPin('4711');
    await Future<void>.delayed(Duration.zero);
    expect(menuShowsEntry(fake), isTrue);

    container.read(historyRevealedProvider.notifier).conceal();
    await Future<void>.delayed(Duration.zero);
    expect(menuShowsEntry(fake), isFalse);
  });
}
