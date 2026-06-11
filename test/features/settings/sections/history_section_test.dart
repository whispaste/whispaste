/// Round-trip widget tests for [HistorySection].
///
/// Covers: max-entries dropdown and auto-trash-days dropdown, both
/// through [settingsProvider].
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/settings/sections/history_section.dart';

import '../../../fixtures/test_helpers.dart';

// ---------------------------------------------------------------------------
// Fake
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

late L10n l10n;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  group('HistorySection', () {
    testWidgets('renders two dropdowns', (tester) async {
      final notifier = _FakeSettingsNotifier(AppSettings.defaults);
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: HistorySection()),
          overrides: [settingsProvider.overrideWith(() => notifier)],
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(DropdownButton<String>), findsNWidgets(2));
    });

    // ── Max entries ─────────────────────────────────────────────────────────

    testWidgets(
      'max-entries dropdown round-trip updates history.historyMaxEntries',
      (tester) async {
        final notifier = _FakeSettingsNotifier(AppSettings.defaults);
        // Default historyMaxEntries = 0 → shown as "Unlimited".
        await tester.pumpWidget(
          makeTestable(
            const SingleChildScrollView(child: HistorySection()),
            overrides: [settingsProvider.overrideWith(() => notifier)],
            locale: const Locale('en'),
          ),
        );
        await tester.pumpAndSettle();

        // Open first dropdown (historyMaxEntries).
        await tester.tap(find.byType(DropdownButton<String>).first);
        await tester.pumpAndSettle();

        // '10' maps to label '10' (no l10n transform for non-zero values).
        await tester.tap(find.text('10').last);
        await tester.pumpAndSettle();

        expect(notifier.state.value!.history.historyMaxEntries, 10);
      },
    );

    // ── Auto-trash days ─────────────────────────────────────────────────────

    testWidgets(
      'auto-trash dropdown round-trip updates history.historyAutoTrashDays',
      (tester) async {
        final notifier = _FakeSettingsNotifier(AppSettings.defaults);
        // Default historyAutoTrashDays = 30 → shown as "30 days".
        await tester.pumpWidget(
          makeTestable(
            const SingleChildScrollView(child: HistorySection()),
            overrides: [settingsProvider.overrideWith(() => notifier)],
            locale: const Locale('en'),
          ),
        );
        await tester.pumpAndSettle();

        // Open second dropdown (historyAutoTrashDays).
        await tester.tap(find.byType(DropdownButton<String>).at(1));
        await tester.pumpAndSettle();

        // Select 7 days — label comes from the plural ICU pattern.
        await tester.tap(
          find.text(l10n.settingsHistoryAutoTrashDaysLabel(7)).last,
        );
        await tester.pumpAndSettle();

        expect(notifier.state.value!.history.historyAutoTrashDays, 7);
      },
    );
  });
}
