/// Widget tests for the "Spoken line breaks" toggle inside
/// [TextProcessingSection]. Mirrors `remove_filler_words_toggle_test.dart`
/// (same cloud-mode setup, same fake notifier), default on.
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

const _toggleKey = Key('spokenPunctuationToggle');

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

AppSettings _cloud({bool? spokenPunctuation}) => AppSettings.defaults
    .copyWith(sttProvider: SttProviderType.openAI.value)
    .copyWithSections(
      stt: spokenPunctuation == null
          ? AppSettings.defaults.stt
          : AppSettings.defaults.stt.copyWith(
              spokenPunctuation: spokenPunctuation,
            ),
    );

Switch _switch(WidgetTester tester) =>
    tester.widget<Switch>(find.byKey(_toggleKey));

void main() {
  late L10n l10n;

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  group('Spoken punctuation toggle', () {
    testWidgets('renders label and subtitle, off by default', (tester) async {
      await _pumpSection(tester, _cloud());

      expect(find.text(l10n.settingsSpokenPunctuation), findsOneWidget);
      expect(find.text(l10n.settingsSpokenPunctuationSubtitle), findsOneWidget);
      expect(_switch(tester).value, isFalse);
    });

    testWidgets('reflects a persisted true value', (tester) async {
      await _pumpSection(tester, _cloud(spokenPunctuation: true));

      expect(_switch(tester).value, isTrue);
    });

    testWidgets('toggling persists the setting', (tester) async {
      final notifier = await _pumpSection(tester, _cloud());

      await tester.ensureVisible(find.byKey(_toggleKey));
      await tester.tap(find.byKey(_toggleKey));
      await tester.pumpAndSettle();

      expect(notifier.current.stt.spokenPunctuation, isTrue);
      expect(_switch(tester).value, isTrue);
    });
  });
}
