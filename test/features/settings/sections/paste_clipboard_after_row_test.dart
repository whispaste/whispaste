/// Widget tests for the "Clipboard after pasting" row in Settings > Text &
/// Einfügen (restore the previous clipboard content or keep the dictation).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/features/settings/sections/feedback_section.dart';
import 'package:whispaste/widgets/wp_dropdown.dart';

import '../../../fixtures/test_helpers.dart';

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

  AppSettings get current => _settings;
}

const _rowKey = ValueKey<String>('settings-paste-clipboard-after');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('defaults to restoring the previous clipboard content', (
    tester,
  ) async {
    final notifier = _FakeSettingsNotifier(AppSettings.defaults);
    await tester.pumpWidget(
      makeTestable(
        const SingleChildScrollView(child: AfterTranscriptionSection()),
        overrides: [settingsProvider.overrideWith(() => notifier)],
      ),
    );
    await tester.pumpAndSettle();

    final dropdown = tester.widget<WpDropdown<String>>(find.byKey(_rowKey));
    expect(dropdown.value, 'restore');
  });

  testWidgets('choosing keep stores restoreClipboardAfterPaste = false', (
    tester,
  ) async {
    final notifier = _FakeSettingsNotifier(AppSettings.defaults);
    await tester.pumpWidget(
      makeTestable(
        const SingleChildScrollView(child: AfterTranscriptionSection()),
        overrides: [settingsProvider.overrideWith(() => notifier)],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(_rowKey));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('settings-paste-clipboard-after-item-keep')),
    );
    await tester.pumpAndSettle();

    expect(notifier.current.behavior.restoreClipboardAfterPaste, isFalse);
    final dropdown = tester.widget<WpDropdown<String>>(find.byKey(_rowKey));
    expect(dropdown.value, 'keep');
  });

  group('legacy restore switch (W-E1)', () {
    const switchKey = ValueKey<String>(
      'settings-paste-clipboard-without-receipt',
    );

    Switch readSwitch(WidgetTester tester) =>
        tester.widget<Switch>(find.byKey(switchKey));

    testWidgets('is off by default and turns on with a tap', (tester) async {
      final notifier = _FakeSettingsNotifier(AppSettings.defaults);
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: AfterTranscriptionSection()),
          overrides: [settingsProvider.overrideWith(() => notifier)],
        ),
      );
      await tester.pumpAndSettle();

      expect(readSwitch(tester).value, isFalse);
      await tester.tap(find.byKey(switchKey));
      await tester.pumpAndSettle();

      expect(notifier.current.behavior.restoreClipboardWithoutReceipt, isTrue);
      expect(readSwitch(tester).value, isTrue);
    });

    testWidgets('is disabled when the dictation is kept on the clipboard', (
      tester,
    ) async {
      final notifier = _FakeSettingsNotifier(
        AppSettings.defaults.copyWithSections(
          behavior: AppSettings.defaults.behavior.copyWith(
            restoreClipboardAfterPaste: false,
          ),
        ),
      );
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: AfterTranscriptionSection()),
          overrides: [settingsProvider.overrideWith(() => notifier)],
        ),
      );
      await tester.pumpAndSettle();

      expect(readSwitch(tester).onChanged, isNull);
    });
  });
}
