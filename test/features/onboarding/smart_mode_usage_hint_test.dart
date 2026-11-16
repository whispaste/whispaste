/// Widget tests for [SmartModeUsageHintWatcher]'s once-only logic.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/data/history_providers.dart';
import 'package:whispaste/features/onboarding/smart_mode_usage_hint.dart';

import '../../fixtures/test_helpers.dart';
import '../../test_helpers/nudge_gate_open.dart';

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

HistoryEntry _entry(String id, String content, DateTime timestamp) =>
    HistoryEntry(
      id: id,
      content: content,
      title: content,
      timestamp: timestamp,
      durationSec: 1,
      processingDurationSec: 0.1,
      language: 'en',
      languageHint: 'en',
      tags: '',
      pinned: false,
      source: 'local',
      model: 'test',
      isLocal: true,
      costUsd: 0,
      archived: false,
      titleEdited: false,
      colorSlot: 0,
    );

/// A [StreamController]-backed override lets a test push successive history
/// snapshots — a plain `Stream.value` only ever emits once, which can't
/// exercise "a *new* entry arrives after the initial catch-up load".
StreamController<List<HistoryEntry>> _historyController() =>
    StreamController<List<HistoryEntry>>.broadcast();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'shows the hint once a new dictation completes with Smart Mode off',
    (tester) async {
      final settings = _FakeSettingsNotifier(
        AppSettings.defaults.copyWithSections(
          onboarding: OnboardingSettings.defaults.copyWith(
            onboardingCompleted: true,
          ),
        ),
      );
      final controller = _historyController();
      addTearDown(controller.close);

      await tester.pumpWidget(
        makeTestable(
          const SmartModeUsageHintWatcher(child: SizedBox.shrink()),
          locale: const Locale('en'),
          overrides: [
            nudgeGateOpenOverride(),
            settingsProvider.overrideWith(() => settings),
            latestRecordingsProvider.overrideWith((ref) => controller.stream),
          ],
        ),
      );
      controller.add([_entry('1', 'hello world', DateTime(2026, 1, 1))]);
      await tester.pumpAndSettle();

      // The initial catch-up emission must not trigger the hint.

      // A genuinely new dictation completes.
      controller.add([
        _entry('2', 'a brand new dictation', DateTime(2026, 1, 2)),
        _entry('1', 'hello world', DateTime(2026, 1, 1)),
      ]);
      await tester.pumpAndSettle();

      await tester.tap(
        find.bySemanticsIdentifier('smart-mode-usage-hint-dismiss'),
      );
      await tester.pumpAndSettle();

      expect(settings.state.value!.onboarding.smartModeUsageHintShown, true);
    },
  );

  testWidgets('never shows when Smart Mode is already engaged', (tester) async {
    final settings = _FakeSettingsNotifier(
      AppSettings.defaults.copyWithSections(
        smartMode: const SmartModeSettings(standardPreset: 'cleanup'),
        onboarding: OnboardingSettings.defaults.copyWith(
          onboardingCompleted: true,
        ),
      ),
    );
    final controller = _historyController();
    addTearDown(controller.close);

    await tester.pumpWidget(
      makeTestable(
        const SmartModeUsageHintWatcher(child: SizedBox.shrink()),
        locale: const Locale('en'),
        overrides: [
          nudgeGateOpenOverride(),
          settingsProvider.overrideWith(() => settings),
          latestRecordingsProvider.overrideWith((ref) => controller.stream),
        ],
      ),
    );
    controller.add([_entry('1', 'hello world', DateTime(2026, 1, 1))]);
    await tester.pumpAndSettle();

    controller.add([
      _entry('2', 'a brand new dictation', DateTime(2026, 1, 2)),
      _entry('1', 'hello world', DateTime(2026, 1, 1)),
    ]);
    await tester.pumpAndSettle();

    expect(settings.state.value!.onboarding.smartModeUsageHintShown, false);
  });
}
