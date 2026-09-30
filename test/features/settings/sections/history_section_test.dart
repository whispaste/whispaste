/// Widget tests for [HistorySection] — retention-preset control.
///
/// AC coverage:
/// (a) Selecting a preset writes the expected (maxEntries, autoTrashDays) pair.
/// (b) A stored combo matching a preset shows that preset label in the dropdown.
/// (c) A stored combo matching no preset shows "Custom" / "Benutzerdefiniert"
///     without overwriting the stored values.
/// (d) Exactly one retention-preset dropdown is present (no two separate ones).
/// (e) The "hide history on open" toggle persists `historyHideOnOpen`
///     without touching the retention fields.
/// PIN lock (`.scratch/history-pin-lock/`):
/// (f) PIN + auto-lock rows only appear while the gate is on or a PIN is set.
/// (g) "Set PIN" stores a verifiable hash; mismatching entries are refused.
/// (h) Removing the PIN, and switching the gate off, require the current PIN.
/// (i) The auto-lock dropdown persists `historyAutoLockMinutes`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/history/data/history_pin.dart';
import 'package:whispaste/features/history/widgets/history_pin_dialogs.dart';
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

  // ── AC (e): hide-on-open toggle ───────────────────────────────────────────

  group('HistorySection hide-on-open toggle (AC e)', () {
    testWidgets('is off by default and persists historyHideOnOpen = true', (
      tester,
    ) async {
      final notifier = _FakeSettingsNotifier(AppSettings.defaults);
      await tester.pumpWidget(_pump(tester, notifier));
      await tester.pumpAndSettle();

      expect(find.text(l10n.settingsHistoryHideOnOpen), findsOneWidget);
      final toggle = find.byType(Switch);
      expect(toggle, findsOneWidget);
      expect(tester.widget<Switch>(toggle).value, isFalse);

      await tester.tap(toggle);
      await tester.pumpAndSettle();

      final history = notifier.state.value!.history;
      expect(history.historyHideOnOpen, isTrue);
      expect(history.historyMaxEntries, 1000);
      expect(history.historyAutoTrashDays, 90);
    });
  });

  // ── PIN lock (AC f–i) ─────────────────────────────────────────────────────

  group('HistorySection PIN lock', () {
    final pin4711 = hashHistoryPin('4711', iterations: 10);

    AppSettings withHistory(HistorySettings h) =>
        AppSettings.defaults.copyWithSections(history: h);

    /// Types into the PIN dialog's field(s) and submits outside the fake
    /// clock — hashing and verification hop to a background isolate.
    Future<void> submit(
      WidgetTester tester,
      String pin, {
      String? repeat,
    }) async {
      await tester.enterText(find.byKey(kHistoryPinFieldKey), pin);
      if (repeat != null) {
        await tester.enterText(find.byKey(kHistoryPinRepeatFieldKey), repeat);
      }
      await tester.runAsync(() async {
        await tester.tap(find.byKey(kHistoryPinSubmitKey));
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      await tester.pumpAndSettle();
    }

    testWidgets('AC(f): PIN rows are hidden while the gate is off', (
      tester,
    ) async {
      await tester.pumpWidget(
        _pump(tester, _FakeSettingsNotifier(AppSettings.defaults)),
      );
      await tester.pumpAndSettle();

      expect(find.text(l10n.settingsHistoryPin), findsNothing);
      expect(find.text(l10n.settingsHistoryAutoLock), findsNothing);
    });

    testWidgets('AC(g): "Set PIN" stores a verifiable hash', (tester) async {
      final notifier = _FakeSettingsNotifier(
        withHistory(const HistorySettings(historyHideOnOpen: true)),
      );
      await tester.pumpWidget(_pump(tester, notifier));
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.historyPinSetTitle));
      await tester.pumpAndSettle();
      await submit(tester, '1234', repeat: '1235');
      expect(find.text(l10n.historyPinMismatch), findsOneWidget);
      expect(notifier.state.value!.history.historyPin, isEmpty);

      await submit(tester, '1234', repeat: '1234');
      // Hashing at the production work factor runs off-isolate; wait for it.
      await tester.runAsync(() async {
        for (var i = 0; i < 100; i++) {
          if (notifier.state.value!.history.historyPin.isNotEmpty) break;
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      });
      await tester.pumpAndSettle();
      final stored = notifier.state.value!.history.historyPin;
      expect(verifyHistoryPin('1234', stored), isTrue);
      expect(find.text(l10n.settingsHistoryPinRemove), findsOneWidget);
    });

    testWidgets('AC(h): removing the PIN requires the current one', (
      tester,
    ) async {
      final notifier = _FakeSettingsNotifier(
        withHistory(
          HistorySettings(historyHideOnOpen: true, historyPin: pin4711),
        ),
      );
      await tester.pumpWidget(_pump(tester, notifier));
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.settingsHistoryPinRemove));
      await tester.pumpAndSettle();
      await submit(tester, '0000');
      expect(find.text(l10n.historyPinWrong), findsOneWidget);
      expect(notifier.state.value!.history.historyPin, pin4711);

      await submit(tester, '4711');
      expect(notifier.state.value!.history.historyPin, isEmpty);
      expect(notifier.state.value!.history.historyHideOnOpen, isTrue);
    });

    testWidgets('AC(h): switching the gate off with a PIN asks for it and '
        'drops the PIN', (tester) async {
      final notifier = _FakeSettingsNotifier(
        withHistory(
          HistorySettings(historyHideOnOpen: true, historyPin: pin4711),
        ),
      );
      await tester.pumpWidget(_pump(tester, notifier));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.byKey(kHistoryPinFieldKey), findsOneWidget);
      await tester.tap(find.text(l10n.actionCancel));
      await tester.pumpAndSettle();
      expect(notifier.state.value!.history.historyHideOnOpen, isTrue);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      await submit(tester, '4711');
      final history = notifier.state.value!.history;
      expect(history.historyHideOnOpen, isFalse);
      expect(history.historyPin, isEmpty);
    });

    testWidgets('AC(i): the auto-lock dropdown persists the minutes', (
      tester,
    ) async {
      final notifier = _FakeSettingsNotifier(
        withHistory(const HistorySettings(historyHideOnOpen: true)),
      );
      await tester.pumpWidget(_pump(tester, notifier));
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.settingsHistoryAutoLockNever));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.settingsHistoryAutoLockMinutes(15)).last);
      await tester.pumpAndSettle();

      expect(notifier.state.value!.history.historyAutoLockMinutes, 15);
    });
  });
}
