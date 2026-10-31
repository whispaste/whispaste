/// Widget tests for the "Remove filler words" toggle inside
/// [TextProcessingSection] (handy-catchup ticket 16). Same cloud-mode
/// setup as `numeric_only_mode_toggle_test.dart`, so the local-only model
/// manager stays out of the tree.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/settings/sections/text_processing_section.dart';

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

const _toggleKey = Key('removeFillerWordsToggle');

Future<_FakeSettingsNotifier> _pumpSection(
  WidgetTester tester,
  AppSettings settings,
) async {
  final notifier = _FakeSettingsNotifier(settings);
  await tester.pumpWidget(
    makeTestable(
      const SingleChildScrollView(child: TextProcessingSection()),
      overrides: [settingsProvider.overrideWith(() => notifier)],
      locale: const Locale('en'),
    ),
  );
  await tester.pumpAndSettle();
  return notifier;
}

AppSettings _cloud({bool removeFillerWords = false}) => AppSettings.defaults
    .copyWith(sttProvider: SttProviderType.openAI.value)
    .copyWithSections(
      stt: AppSettings.defaults.stt.copyWith(
        removeFillerWords: removeFillerWords,
      ),
    );

Switch _switch(WidgetTester tester) =>
    tester.widget<Switch>(find.byKey(_toggleKey));

void main() {
  late L10n l10n;

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  group('Remove filler words toggle', () {
    testWidgets('renders label and subtitle, off by default', (tester) async {
      await _pumpSection(tester, _cloud());

      expect(find.text(l10n.settingsRemoveFillerWords), findsOneWidget);
      expect(find.text(l10n.settingsRemoveFillerWordsSubtitle), findsOneWidget);
      expect(_switch(tester).value, isFalse);
    });

    testWidgets('reflects a persisted true value', (tester) async {
      await _pumpSection(tester, _cloud(removeFillerWords: true));

      expect(_switch(tester).value, isTrue);
    });

    testWidgets('toggling persists the setting', (tester) async {
      final notifier = await _pumpSection(tester, _cloud());

      await tester.ensureVisible(find.byKey(_toggleKey));
      await tester.tap(find.byKey(_toggleKey));
      await tester.pumpAndSettle();

      expect(notifier.current.stt.removeFillerWords, isTrue);
      expect(_switch(tester).value, isTrue);
    });

    // A text transform after transcription, so it applies to every engine.
    for (final engine in OnDeviceEngine.values) {
      testWidgets('renders for on-device engine ${engine.value}', (
        tester,
      ) async {
        await _pumpSection(
          tester,
          AppSettings.defaults.copyWith(sttEngine: engine.value),
        );

        expect(find.byKey(_toggleKey), findsOneWidget);
      });
    }
  });
}
