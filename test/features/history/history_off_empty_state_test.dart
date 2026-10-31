/// Recordings page while "Aufnahmen speichern" is off and nothing is stored
/// (history-off feature): a clear empty state that says why and offers the way
/// to the switch. Checked at 800 px with text scaling 1.3.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/history/data/providers.dart';
import 'package:whispaste/features/history/history_page.dart';

import '../../fixtures/test_helpers.dart';

class _FakeSettingsNotifier extends SettingsNotifier {
  _FakeSettingsNotifier(this._settings);

  final AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    state = AsyncData(updater(state.value ?? _settings));
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required bool saveHistory,
  Size size = const Size(800, 1000),
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    makeTestable(
      MediaQuery(
        data: MediaQueryData(size: size),
        child: const HistoryPage(),
      ),
      size: size,
      locale: locale,
      overrides: [
        historyEntriesProvider.overrideWith((ref) => Stream.value(const [])),
        archivedEntriesProvider.overrideWith((ref) => Stream.value(const [])),
        trashEntriesProvider.overrideWith((ref) => Stream.value(const [])),
        settingsProvider.overrideWith(
          () => _FakeSettingsNotifier(
            AppSettings(history: HistorySettings(saveHistory: saveHistory)),
          ),
        ),
      ],
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late L10n l10n;
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  testWidgets('with saving off and nothing stored, the page says why and '
      'offers the way to the switch', (tester) async {
    await _pump(tester, saveHistory: false);

    expect(find.text(l10n.historyOffTitle), findsOneWidget);
    expect(find.text(l10n.historyOffHint), findsOneWidget);
    expect(find.text(l10n.historyOffAction), findsOneWidget);
  });

  testWidgets(
    'with saving on and nothing stored, the normal empty state shows',
    (tester) async {
      await _pump(tester, saveHistory: true);

      expect(find.text(l10n.historyOffTitle), findsNothing);
      expect(find.text(l10n.historyEmpty), findsOneWidget);
    },
  );
}
