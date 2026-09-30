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
library;

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/history/data/providers.dart';
import 'package:whispaste/features/history/data/sample_data.dart';
import 'package:whispaste/features/history/history_page.dart';

import '../../fixtures/test_helpers.dart';

class _FakeSettingsNotifier extends SettingsNotifier {
  _FakeSettingsNotifier(this._settings);
  final AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;
}

const _sampleTitle = 'Meeting notes — Product roadmap Q3';

late L10n l10n;

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required bool hideOnOpen,
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
              history: HistorySettings(historyHideOnOpen: hideOnOpen),
            ),
          ),
        ),
        historyEntriesProvider.overrideWith((ref) => Stream.value(active)),
        archivedEntriesProvider.overrideWith((ref) => Stream.value(const [])),
        trashEntriesProvider.overrideWith((ref) => Stream.value(const [])),
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
}
