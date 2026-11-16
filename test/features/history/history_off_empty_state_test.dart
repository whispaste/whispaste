/// Recordings page while "Aufnahmen speichern" is off and nothing is stored
/// (history-off feature): a clear empty state that says why and offers the way
/// to the switch. Checked at 800 px with text scaling 1.3. Also the one first
/// action of the plain and the trash empty state (#1076).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/features/history/data/providers.dart';
import 'package:whispaste/features/history/history_page.dart';
import 'package:whispaste/services/recording_orchestrator.dart';
import 'package:whispaste/services/smart_mode/smart_mode_presets.dart';

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

class _CountingOrchestrator extends RecordingOrchestrator {
  int toggles = 0;

  @override
  void build() {}

  @override
  Future<void> toggleRecording({
    RecordingTarget target = RecordingTarget.clipboard,
    SmartModePreset? forcedSmartModePreset,
    String? languageOverride,
    double? silenceTimeoutOverride,
  }) async {
    toggles++;
  }
}

late _CountingOrchestrator _orchestrator;

class _FixedFilter extends HistoryFilterNotifier {
  _FixedFilter(this._initial);

  final HistoryFilter _initial;

  @override
  HistoryFilter build() => _initial;
}

Future<void> _pump(
  WidgetTester tester, {
  required bool saveHistory,
  Size size = const Size(800, 1000),
  Locale locale = const Locale('en'),
  HistoryFilter filter = HistoryFilter.all,
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
        pagedHistoryProvider.overrideWith((ref) => Stream.value(const [])),
        archivedEntriesProvider.overrideWith((ref) => Stream.value(const [])),
        trashEntriesProvider.overrideWith((ref) => Stream.value(const [])),
        recordingOrchestratorProvider.overrideWith(
          () => _orchestrator = _CountingOrchestrator(),
        ),
        historyFilterProvider.overrideWith(() => _FixedFilter(filter)),
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

  testWidgets('the plain empty state offers "Dictate" as its one action', (
    tester,
  ) async {
    await _pump(tester, saveHistory: true);

    final dictate = find.byKey(const ValueKey('history-empty-dictate'));
    expect(dictate, findsOneWidget);
    await tester.tap(dictate);
    await tester.pump();
    expect(_orchestrator.toggles, 1);
  });

  testWidgets('the empty trash leads back to all recordings', (tester) async {
    await _pump(tester, saveHistory: true, filter: HistoryFilter.trash);

    await tester.tap(find.byKey(const ValueKey('history-trash-show-all')));
    await tester.pumpAndSettle();
    expect(find.text(l10n.historyTrashEmpty), findsNothing);
    expect(find.text(l10n.historyEmpty), findsOneWidget);
  });
}
