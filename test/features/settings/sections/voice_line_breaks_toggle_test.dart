/// Widget tests for the "Spoken line breaks" toggle inside
/// [SpeechRecognitionSection]. Mirrors `remove_filler_words_toggle_test.dart`
/// (same cloud-mode setup, same fake notifier), default on.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/settings/sections/stt_section.dart';

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

const _toggleKey = Key('voiceLineBreaksToggle');

Future<_FakeSettingsNotifier> _pumpSection(
  WidgetTester tester,
  AppSettings settings,
) async {
  final notifier = _FakeSettingsNotifier(settings);
  await tester.pumpWidget(
    makeTestable(
      const SingleChildScrollView(child: SpeechRecognitionSection()),
      overrides: [settingsProvider.overrideWith(() => notifier)],
      locale: const Locale('en'),
    ),
  );
  await tester.pumpAndSettle();
  return notifier;
}

AppSettings _cloud({bool? voiceLineBreaks}) => AppSettings.defaults
    .copyWith(sttProvider: SttProviderType.openAI.value)
    .copyWithSections(
      stt: voiceLineBreaks == null
          ? AppSettings.defaults.stt
          : AppSettings.defaults.stt.copyWith(voiceLineBreaks: voiceLineBreaks),
    );

Switch _switch(WidgetTester tester) =>
    tester.widget<Switch>(find.byKey(_toggleKey));

void main() {
  late L10n l10n;

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  group('Spoken line breaks toggle', () {
    testWidgets('renders label and subtitle, on by default', (tester) async {
      await _pumpSection(tester, _cloud());

      expect(find.text(l10n.settingsVoiceLineBreaks), findsOneWidget);
      expect(find.text(l10n.settingsVoiceLineBreaksSubtitle), findsOneWidget);
      expect(_switch(tester).value, isTrue);
    });

    testWidgets('reflects a persisted false value', (tester) async {
      await _pumpSection(tester, _cloud(voiceLineBreaks: false));

      expect(_switch(tester).value, isFalse);
    });

    testWidgets('toggling persists the setting', (tester) async {
      final notifier = await _pumpSection(tester, _cloud());

      await tester.ensureVisible(find.byKey(_toggleKey));
      await tester.tap(find.byKey(_toggleKey));
      await tester.pumpAndSettle();

      expect(notifier.current.stt.voiceLineBreaks, isFalse);
      expect(_switch(tester).value, isFalse);
    });
  });
}
