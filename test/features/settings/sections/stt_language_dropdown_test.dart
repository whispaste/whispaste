/// Tests for the recognition-language row inside [SpeechRecognitionSection].
///
/// WP-23e wiring: the row shows the current choice and opens the language
/// dialog (`WpLanguageDialog`). These tests pin the contract:
///
///  - the dialog offers every [whisperLanguages] entry;
///  - saving a selection persists its short code (not a display name);
///  - legacy persisted display values (e.g. 'German') and stored codes both
///    render the correct current language on the row.
///
/// Uses a cloud-mode settings override so the local-only WpSttModelManager /
/// BenchmarkButton stay out of the tree (same approach as
/// custom_vocabulary_test.dart).
library;

import 'package:flutter/material.dart';
import 'package:flutter_localized_locales/flutter_localized_locales.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/whisper_languages.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/settings/sections/stt_section.dart';
import 'package:whispaste/features/settings/widgets/wp_language_dialog.dart';

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

late L10n l10n;

Widget _scrollable(Widget child) => SingleChildScrollView(child: child);

AppSettings _cloudSettings({String language = 'Auto-detect'}) {
  return AppSettings.defaults.copyWith(
    sttProvider: SttProviderType.openAI.value,
    sttLanguage: language,
  );
}

Future<_FakeSettingsNotifier> _pumpSection(
  WidgetTester tester, {
  String language = 'Auto-detect',
}) async {
  final notifier = _FakeSettingsNotifier(_cloudSettings(language: language));
  await tester.pumpWidget(
    makeTestable(
      _scrollable(const SpeechRecognitionSection()),
      overrides: [settingsProvider.overrideWith(() => notifier)],
      locale: const Locale('en'),
    ),
  );
  await tester.pumpAndSettle();
  return notifier;
}

Finder _openDialogButton() =>
    find.byKey(const ValueKey('settings-stt-language-change'));

/// Localised name of [code] as the row renders it (same lookup as the section).
String _nameOf(WidgetTester tester, String code) =>
    LocaleNames.of(
      tester.element(find.byType(SpeechRecognitionSection)),
    )?.nameOf(code) ??
    whisperLanguages[code]!;

void main() {
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  group('Recognition-language row', () {
    testWidgets('opens the dialog offering the full 99-language catalog', (
      tester,
    ) async {
      await _pumpSection(tester);
      await tester.tap(_openDialogButton());
      await tester.pumpAndSettle();

      final dialog = tester.widget<WpLanguageDialog>(
        find.byType(WpLanguageDialog),
      );
      expect(dialog.options.length, whisperLanguages.length);
      expect(
        dialog.options.map((o) => o.code).toSet(),
        whisperLanguages.keys.toSet(),
      );
    });

    testWidgets('saving Russian in the dialog persists the short code ru', (
      tester,
    ) async {
      final notifier = await _pumpSection(tester);
      await tester.tap(_openDialogButton());
      await tester.pumpAndSettle();

      // Drive the save through the dialog's own callback instead of scrolling
      // the tile grid (flaky in widget tests). The catalog test above already
      // pins that 'ru' is one of the offered options.
      final dialog = tester.widget<WpLanguageDialog>(
        find.byType(WpLanguageDialog),
      );
      expect(dialog.options.map((o) => o.code), contains('ru'));
      dialog.onSave(
        const WpLanguageSelection(autoDetect: false, codes: ['ru']),
      );
      await tester.pumpAndSettle();

      expect(notifier.current.sttLanguage, 'ru');
      expect(notifier.current.sttLanguageCode, 'ru');
    });

    testWidgets('legacy persisted display value shows its language', (
      tester,
    ) async {
      await _pumpSection(tester, language: 'German');
      expect(find.text(_nameOf(tester, 'de')), findsOneWidget);
    });

    testWidgets('persisted short code shows its language', (tester) async {
      await _pumpSection(tester, language: 'ru');
      expect(find.text(_nameOf(tester, 'ru')), findsOneWidget);
    });

    testWidgets('auto-detect stays the localized first entry', (tester) async {
      await _pumpSection(tester);
      expect(find.text(l10n.settingsLanguageAutoDetect), findsOneWidget);
    });
  });
}
