/// Tests for the recognition-language dropdown inside
/// [SpeechRecognitionSection].
///
/// Store-review regression (June 2026): the dropdown offered only four
/// languages although the bundled Whisper models support 99. These tests
/// pin the new contract:
///
///  - the dropdown offers Auto-detect plus every [whisperLanguages] entry;
///  - selecting a language persists its short code (not a display name);
///  - legacy persisted display values (e.g. 'German') and stored codes
///    both render the correct selection.
///
/// Uses a cloud-mode settings override so the local-only SttModelManager /
/// BenchmarkButton stay out of the tree (same approach as
/// custom_vocabulary_test.dart).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/whisper_languages.dart';
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

/// The recognition-language dropdown is the one whose current value is a
/// catalog code or 'auto'.
Finder _languageDropdown() => find.byWidgetPredicate(
  (w) =>
      w is DropdownButton<String> &&
      (w.value == 'auto' || whisperLanguages.containsKey(w.value)),
);

void main() {
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  group('Recognition-language dropdown', () {
    testWidgets('offers Auto-detect plus the full 99-language catalog', (
      tester,
    ) async {
      await _pumpSection(tester);

      final dropdown = tester.widget<DropdownButton<String>>(
        _languageDropdown(),
      );
      final values = dropdown.items!.map((i) => i.value).toList();

      expect(values.first, 'auto');
      expect(values.length, 1 + whisperLanguages.length);
      expect(values.toSet(), {'auto', ...whisperLanguages.keys});
    });

    testWidgets('selecting Russian persists the short code ru', (tester) async {
      final notifier = await _pumpSection(tester);

      // Drive the selection through the widget's own onChanged instead of
      // scrolling the ~100-entry overlay menu (flaky in widget tests). The
      // "offers the full catalog" test already pins that 'ru' is a real
      // menu entry.
      final dropdown = tester.widget<DropdownButton<String>>(
        _languageDropdown(),
      );
      expect(
        dropdown.items!.map((i) => i.value),
        contains('ru'),
        reason: 'Russian must be selectable from the menu',
      );
      dropdown.onChanged!('ru');
      await tester.pumpAndSettle();

      expect(notifier.current.sttLanguage, 'ru');
      expect(notifier.current.sttLanguageCode, 'ru');
    });

    testWidgets('legacy persisted display value renders its language', (
      tester,
    ) async {
      await _pumpSection(tester, language: 'German');

      final dropdown = tester.widget<DropdownButton<String>>(
        _languageDropdown(),
      );
      expect(dropdown.value, 'de');
    });

    testWidgets('persisted short code renders its language', (tester) async {
      await _pumpSection(tester, language: 'ru');

      final dropdown = tester.widget<DropdownButton<String>>(
        _languageDropdown(),
      );
      expect(dropdown.value, 'ru');
    });

    testWidgets('auto-detect stays the localized first entry', (tester) async {
      await _pumpSection(tester);

      expect(find.text(l10n.settingsLanguageAutoDetect), findsOneWidget);
    });
  });
}
