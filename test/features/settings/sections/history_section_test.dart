/// Widget tests for [HistorySection] — retention-preset control.
///
/// AC coverage:
/// (a) Selecting a preset writes the expected (maxEntries, autoTrashDays) pair.
/// (b) A stored combo matching a preset shows that preset label in the dropdown.
/// (c) A stored combo matching no preset shows "Custom" / "Benutzerdefiniert"
///     without overwriting the stored values.
/// (d) Exactly one retention-preset dropdown is present (no two separate ones).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/settings/sections/history_section.dart';

import '../../../fixtures/test_helpers.dart';

// ---------------------------------------------------------------------------
// Fake notifier
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
// Helpers
// ---------------------------------------------------------------------------

Widget _pump(WidgetTester tester, _FakeSettingsNotifier notifier) =>
    makeTestable(
      const SingleChildScrollView(child: HistorySection()),
      overrides: [settingsProvider.overrideWith(() => notifier)],
      locale: const Locale('en'),
    );

/// Returns the single retention preset DropdownButton.
Finder _presetDropdown() => find.byWidgetPredicate(
  (w) =>
      w is DropdownButton<String> &&
      (w.items?.any(
            (i) =>
                i.value == HistoryRetentionPreset.minimal.name ||
                i.value == HistoryRetentionPreset.standard.name ||
                i.value == HistoryRetentionPreset.unlimited.name,
          ) ??
          false),
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

late L10n l10n;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  // ── AC (d): exactly one dropdown ─────────────────────────────────────────

  group('HistorySection structure', () {
    testWidgets('AC(d): renders exactly one retention preset dropdown', (
      tester,
    ) async {
      final notifier = _FakeSettingsNotifier(AppSettings.defaults);
      await tester.pumpWidget(_pump(tester, notifier));
      await tester.pumpAndSettle();

      expect(find.byType(DropdownButton<String>), findsOneWidget);
    });
  });

  // ── AC (b): stored combo → correct preset label ───────────────────────────

  group('HistorySection preset detection (AC b)', () {
    testWidgets('shows Minimal when maxEntries=100 autoTrashDays=30', (
      tester,
    ) async {
      final notifier = _FakeSettingsNotifier(
        const AppSettings(
          history: HistorySettings(
            historyMaxEntries: 100,
            historyAutoTrashDays: 30,
          ),
        ),
      );
      await tester.pumpWidget(_pump(tester, notifier));
      await tester.pumpAndSettle();

      final btn = tester.widget<DropdownButton<String>>(_presetDropdown());
      expect(btn.value, HistoryRetentionPreset.minimal.name);
    });

    testWidgets('shows Standard when maxEntries=1000 autoTrashDays=90', (
      tester,
    ) async {
      final notifier = _FakeSettingsNotifier(
        const AppSettings(
          history: HistorySettings(
            historyMaxEntries: 1000,
            historyAutoTrashDays: 90,
          ),
        ),
      );
      await tester.pumpWidget(_pump(tester, notifier));
      await tester.pumpAndSettle();

      final btn = tester.widget<DropdownButton<String>>(_presetDropdown());
      expect(btn.value, HistoryRetentionPreset.standard.name);
    });

    testWidgets('shows Unlimited when maxEntries=0 autoTrashDays=0', (
      tester,
    ) async {
      final notifier = _FakeSettingsNotifier(
        const AppSettings(
          history: HistorySettings(
            historyMaxEntries: 0,
            historyAutoTrashDays: 0,
          ),
        ),
      );
      await tester.pumpWidget(_pump(tester, notifier));
      await tester.pumpAndSettle();

      final btn = tester.widget<DropdownButton<String>>(_presetDropdown());
      expect(btn.value, HistoryRetentionPreset.unlimited.name);
    });
  });

  // ── AC (a): preset selection writes both fields ───────────────────────────

  group('HistorySection preset selection (AC a)', () {
    testWidgets('selecting Minimal writes maxEntries=100, autoTrashDays=30', (
      tester,
    ) async {
      // Start from Unlimited so Minimal is a different choice.
      final notifier = _FakeSettingsNotifier(
        const AppSettings(
          history: HistorySettings(
            historyMaxEntries: 0,
            historyAutoTrashDays: 0,
          ),
        ),
      );
      await tester.pumpWidget(_pump(tester, notifier));
      await tester.pumpAndSettle();

      await tester.tap(_presetDropdown());
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate(
          (w) =>
              w is DropdownMenuItem<String> &&
              w.value == HistoryRetentionPreset.minimal.name,
        ),
      );
      await tester.pumpAndSettle();

      expect(notifier.state.value!.history.historyMaxEntries, 100);
      expect(notifier.state.value!.history.historyAutoTrashDays, 30);
    });

    testWidgets('selecting Standard writes maxEntries=1000, autoTrashDays=90', (
      tester,
    ) async {
      final notifier = _FakeSettingsNotifier(
        const AppSettings(
          history: HistorySettings(
            historyMaxEntries: 0,
            historyAutoTrashDays: 0,
          ),
        ),
      );
      await tester.pumpWidget(_pump(tester, notifier));
      await tester.pumpAndSettle();

      await tester.tap(_presetDropdown());
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate(
          (w) =>
              w is DropdownMenuItem<String> &&
              w.value == HistoryRetentionPreset.standard.name,
        ),
      );
      await tester.pumpAndSettle();

      expect(notifier.state.value!.history.historyMaxEntries, 1000);
      expect(notifier.state.value!.history.historyAutoTrashDays, 90);
    });

    testWidgets('selecting Unlimited writes maxEntries=0, autoTrashDays=0', (
      tester,
    ) async {
      final notifier = _FakeSettingsNotifier(
        const AppSettings(
          history: HistorySettings(
            historyMaxEntries: 100,
            historyAutoTrashDays: 30,
          ),
        ),
      );
      await tester.pumpWidget(_pump(tester, notifier));
      await tester.pumpAndSettle();

      await tester.tap(_presetDropdown());
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate(
          (w) =>
              w is DropdownMenuItem<String> &&
              w.value == HistoryRetentionPreset.unlimited.name,
        ),
      );
      await tester.pumpAndSettle();

      expect(notifier.state.value!.history.historyMaxEntries, 0);
      expect(notifier.state.value!.history.historyAutoTrashDays, 0);
    });
  });

  // ── AC (c): custom combo → "Custom" shown, values not overwritten ─────────

  group('HistorySection custom preset (AC c)', () {
    testWidgets(
      'stored combo matching no preset shows Custom without overwriting values',
      (tester) async {
        // (200, 60) matches no preset → should show 'custom'.
        final notifier = _FakeSettingsNotifier(
          const AppSettings(
            history: HistorySettings(
              historyMaxEntries: 200,
              historyAutoTrashDays: 60,
            ),
          ),
        );
        await tester.pumpWidget(_pump(tester, notifier));
        await tester.pumpAndSettle();

        final btn = tester.widget<DropdownButton<String>>(_presetDropdown());
        expect(btn.value, HistoryRetentionPreset.custom.name);

        // Values must remain untouched — no onChanged side-effect.
        expect(notifier.state.value!.history.historyMaxEntries, 200);
        expect(notifier.state.value!.history.historyAutoTrashDays, 60);
      },
    );

    testWidgets('custom label appears in the dropdown list', (tester) async {
      final notifier = _FakeSettingsNotifier(
        const AppSettings(
          history: HistorySettings(
            historyMaxEntries: 50,
            historyAutoTrashDays: 14,
          ),
        ),
      );
      await tester.pumpWidget(_pump(tester, notifier));
      await tester.pumpAndSettle();

      expect(find.text(l10n.settingsHistoryPresetCustom), findsOneWidget);
    });
  });

  // ── resolveRetentionPreset unit tests ─────────────────────────────────────

  group('resolveRetentionPreset', () {
    test('minimal: 100 / 30', () {
      expect(resolveRetentionPreset(100, 30), HistoryRetentionPreset.minimal);
    });
    test('standard: 1000 / 90', () {
      expect(resolveRetentionPreset(1000, 90), HistoryRetentionPreset.standard);
    });
    test('unlimited: 0 / 0', () {
      expect(resolveRetentionPreset(0, 0), HistoryRetentionPreset.unlimited);
    });
    test('custom: anything else', () {
      expect(resolveRetentionPreset(500, 30), HistoryRetentionPreset.custom);
      expect(resolveRetentionPreset(0, 30), HistoryRetentionPreset.custom);
      expect(resolveRetentionPreset(100, 0), HistoryRetentionPreset.custom);
    });
    test(
      'default HistorySettings resolves to standard (no "Custom" on first run)',
      () {
        const defaults = HistorySettings();
        expect(
          resolveRetentionPreset(
            defaults.historyMaxEntries,
            defaults.historyAutoTrashDays,
          ),
          HistoryRetentionPreset.standard,
        );
      },
    );
  });
}
