/// Widget tests for the history privacy gate — the "Show history" screen the
/// History page shows instead of transcripts while
/// `HistorySettings.historyHideOnOpen` is on (user feedback 571d5361: a
/// shared computer opened straight into the owner's past dictations).
///
/// AC coverage:
/// (a) Setting off (default): the page renders entries as before, no gate.
/// (b) Setting on: the gate is shown and no transcript text is rendered.
/// (c) Tapping "Show history" reveals the entries.
/// (d) Concealing again (what hiding the window does) brings the gate back.
/// PIN lock (`.scratch/history-pin-lock/`):
/// (e) With a PIN the gate asks for it; a wrong PIN is refused, the right
///     one reveals the entries.
/// (f) "Forgot PIN?" → confirm wipes the history and reveals the page.
/// (g) Auto-lock conceals after the configured inactivity; activity on the
///     page restarts the countdown.
library;

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/history/data/history_lock.dart';
import 'package:whispaste/features/history/data/history_pin.dart';
import 'package:whispaste/features/history/data/providers.dart';
import 'package:whispaste/features/history/data/sample_data.dart';
import 'package:whispaste/features/history/history_page.dart';
import 'package:whispaste/features/history/widgets/history_pin_dialogs.dart';

import '../../fixtures/test_helpers.dart';

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

// Cheap work factor keeps the test fast; verification reads it from the hash.
final _pin4711 = hashHistoryPin('4711', iterations: 10);

const _sampleTitle = 'Meeting notes — Product roadmap Q3';

late L10n l10n;

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required bool hideOnOpen,
  String pin = '',
  int autoLockMinutes = 0,
  Future<void> Function()? wiper,
}) async {
  final all = generateSampleEntries();
  final active = all.where((e) => e.deletedAt == null && !e.archived).toList();
  await tester.pumpWidget(
    makeTestable(
      const HistoryPage(),
      locale: const Locale('en'),
      overrides: [
        settingsProvider.overrideWith(
          () => _FakeSettingsNotifier(
            AppSettings(
              history: HistorySettings(
                historyHideOnOpen: hideOnOpen,
                historyPin: pin,
                historyAutoLockMinutes: autoLockMinutes,
              ),
            ),
          ),
        ),
        historyEntriesProvider.overrideWith((ref) => Stream.value(active)),
        archivedEntriesProvider.overrideWith((ref) => Stream.value(const [])),
        trashEntriesProvider.overrideWith((ref) => Stream.value(const [])),
        if (wiper != null) historyWiperProvider.overrideWithValue(wiper),
      ],
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(HistoryPage)));
}

void main() {
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  testWidgets('AC(a): setting off renders entries without a gate', (
    tester,
  ) async {
    await _pump(tester, hideOnOpen: false);

    expect(find.byKey(kHistoryPrivacyGateKey), findsNothing);
    expect(find.text(_sampleTitle), findsOneWidget);
  });

  testWidgets('AC(b): setting on shows the gate and no transcripts', (
    tester,
  ) async {
    await _pump(tester, hideOnOpen: true);

    expect(find.byKey(kHistoryPrivacyGateKey), findsOneWidget);
    expect(find.text(l10n.historyPrivacyGateTitle), findsOneWidget);
    expect(find.text(l10n.historyPrivacyGateShow), findsOneWidget);
    expect(find.text(_sampleTitle), findsNothing);
    expect(find.text(l10n.historySearchTranscriptions), findsNothing);
  });

  testWidgets('AC(c): "Show history" reveals the entries', (tester) async {
    await _pump(tester, hideOnOpen: true);

    await tester.tap(find.text(l10n.historyPrivacyGateShow));
    await tester.pumpAndSettle();

    expect(find.byKey(kHistoryPrivacyGateKey), findsNothing);
    expect(find.text(_sampleTitle), findsOneWidget);
  });

  testWidgets('AC(d): concealing again brings the gate back', (tester) async {
    final container = await _pump(tester, hideOnOpen: true);

    await tester.tap(find.text(l10n.historyPrivacyGateShow));
    await tester.pumpAndSettle();
    expect(find.text(_sampleTitle), findsOneWidget);

    container.read(historyRevealedProvider.notifier).conceal();
    await tester.pumpAndSettle();

    expect(find.byKey(kHistoryPrivacyGateKey), findsOneWidget);
    expect(find.text(_sampleTitle), findsNothing);
  });

  /// Types [pin] into the PIN dialog and submits it. Runs outside the fake
  /// clock because verification hops to a background isolate.
  Future<void> submitPin(WidgetTester tester, String pin) async {
    await tester.enterText(find.byKey(kHistoryPinFieldKey), pin);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(kHistoryPinSubmitKey));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
  }

  testWidgets('AC(e): with a PIN the gate refuses a wrong PIN, accepts the '
      'right one', (tester) async {
    await _pump(tester, hideOnOpen: true, pin: _pin4711);

    expect(find.text(l10n.historyPinGateTitle), findsOneWidget);
    expect(find.text(l10n.historyPrivacyGateShow), findsNothing);

    await tester.tap(find.text(l10n.historyPinUnlock));
    await tester.pumpAndSettle();
    await submitPin(tester, '0000');
    expect(find.text(l10n.historyPinWrong), findsOneWidget);
    expect(find.text(_sampleTitle), findsNothing);

    await submitPin(tester, '4711');
    expect(find.byKey(kHistoryPrivacyGateKey), findsNothing);
    expect(find.text(_sampleTitle), findsOneWidget);
  });

  testWidgets('AC(e): a PIN keeps the gate even with hide-on-open off', (
    tester,
  ) async {
    await _pump(tester, hideOnOpen: false, pin: _pin4711);

    expect(find.byKey(kHistoryPrivacyGateKey), findsOneWidget);
    expect(find.text(_sampleTitle), findsNothing);
  });

  testWidgets('AC(f): "Forgot PIN?" wipes the history after confirming', (
    tester,
  ) async {
    var wipes = 0;
    final container = await _pump(
      tester,
      hideOnOpen: true,
      pin: _pin4711,
      wiper: () async => wipes++,
    );

    await tester.tap(find.text(l10n.historyPinUnlock));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(kHistoryPinForgotKey));
    await tester.pumpAndSettle();
    expect(find.text(l10n.historyPinForgotConfirmTitle), findsOneWidget);
    await tester.tap(find.text(l10n.historyPinForgotConfirmAction));
    await tester.pumpAndSettle();

    expect(wipes, 1);
    expect(container.read(settingsProvider).value!.history.historyPin, isEmpty);
    expect(find.byKey(kHistoryPrivacyGateKey), findsNothing);
  });

  testWidgets('AC(g): auto-lock after inactivity, activity restarts it', (
    tester,
  ) async {
    await _pump(tester, hideOnOpen: true, autoLockMinutes: 1);

    await tester.tap(find.text(l10n.historyPrivacyGateShow));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 50));
    await tester.tap(find.text(_sampleTitle));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 50));
    expect(find.byKey(kHistoryPrivacyGateKey), findsNothing);

    await tester.pump(const Duration(seconds: 15));
    await tester.pumpAndSettle();
    expect(find.byKey(kHistoryPrivacyGateKey), findsOneWidget);
  });
}
