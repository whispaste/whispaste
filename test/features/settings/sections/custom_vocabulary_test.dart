/// Tests for the custom vocabulary field inside [SpeechRecognitionSection].
///
/// _CustomVocabularyField is private; the smallest public surface that
/// contains it is SpeechRecognitionSection.  We drive it through that
/// widget using a cloud-mode settings override so we avoid the local-only
/// SttModelManager / BenchmarkButton sections (which need additional
/// provider stubs not relevant here).
///
/// Covers: initial value renders, placeholder text, hint text,
/// text input writes customVocabulary through settingsProvider (debounced).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData;
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/settings/sections/stt_section.dart';

import '../../../fixtures/test_helpers.dart';

// ---------------------------------------------------------------------------
// Fake settings notifier — captures updateSettings without DB
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

late L10n l10n;

// Helper: SpeechRecognitionSection needs to scroll in the test scaffold.
Widget _scrollable(Widget child) => SingleChildScrollView(child: child);

void main() {
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  group('_CustomVocabularyField (via SpeechRecognitionSection)', () {
    // Use OpenAI provider to skip local-only SttModelManager + BenchmarkButton.
    AppSettings cloudSettings({String vocabulary = ''}) {
      return AppSettings.defaults.copyWith(
        sttProvider: SttProviderType.openAI.value,
        customVocabulary: vocabulary,
      );
    }

    // -------------------------------------------------------------------------
    // 1. Section label and hint text
    // -------------------------------------------------------------------------

    testWidgets('shows custom vocabulary section label and hint', (
      tester,
    ) async {
      final notifier = _FakeSettingsNotifier(cloudSettings());
      await tester.pumpWidget(
        makeTestable(
          _scrollable(const SpeechRecognitionSection()),
          overrides: [settingsProvider.overrideWith(() => notifier)],
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(l10n.settingsCustomVocabulary), findsOneWidget);
      expect(find.text(l10n.settingsCustomVocabularyHint), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // 2. Placeholder text
    // -------------------------------------------------------------------------

    testWidgets('shows placeholder when vocabulary is empty', (tester) async {
      final notifier = _FakeSettingsNotifier(cloudSettings());
      await tester.pumpWidget(
        makeTestable(
          _scrollable(const SpeechRecognitionSection()),
          overrides: [settingsProvider.overrideWith(() => notifier)],
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      // Placeholder text is visible when the vocabulary field is empty
      expect(
        find.text(l10n.settingsCustomVocabularyPlaceholder),
        findsOneWidget,
      );
    });

    // -------------------------------------------------------------------------
    // 3. Initial value pre-fills the field
    // -------------------------------------------------------------------------

    testWidgets('pre-fills the text field with the initial vocabulary value', (
      tester,
    ) async {
      const preloaded = 'whisper Kotlin Flutter';
      final notifier = _FakeSettingsNotifier(
        cloudSettings(vocabulary: preloaded),
      );
      await tester.pumpWidget(
        makeTestable(
          _scrollable(const SpeechRecognitionSection()),
          overrides: [settingsProvider.overrideWith(() => notifier)],
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      // The multi-line vocabulary TextField should show the pre-loaded text
      expect(find.text(preloaded), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // 4. Typing updates the provider after the 600 ms debounce
    // -------------------------------------------------------------------------

    testWidgets(
      'entering text updates customVocabulary in settingsProvider after debounce',
      (tester) async {
        final notifier = _FakeSettingsNotifier(cloudSettings());
        await tester.pumpWidget(
          makeTestable(
            _scrollable(const SpeechRecognitionSection()),
            overrides: [settingsProvider.overrideWith(() => notifier)],
            locale: const Locale('en'),
          ),
        );
        await tester.pumpAndSettle();

        // The custom vocabulary field is a multi-line TextField.
        // We identify it via the bookType icon that precedes it.
        final bookIcon = find.byIcon(LucideIcons.bookType);
        expect(bookIcon, findsOneWidget);

        // Find the TextField that follows the bookType icon by looking for
        // a TextField in the same subtree region (last TextField in the section).
        // The section contains: provider dropdown, API-key field, language
        // dropdown, and the vocabulary field — vocabulary is the last one.
        final vocabField = find.byType(TextField).last;
        await tester.tap(vocabField);
        await tester.enterText(vocabField, 'Riverpod Drift Flutter');
        // Pump one frame so onChanged fires
        await tester.pump();

        // Verify not written yet (debounce is still pending)
        expect(
          notifier.state.value?.stt.customVocabulary,
          isNot('Riverpod Drift Flutter'),
        );

        // Advance past the 600 ms debounce
        await tester.pump(const Duration(milliseconds: 700));

        expect(
          notifier.state.value?.stt.customVocabulary,
          'Riverpod Drift Flutter',
          reason: 'customVocabulary should be updated after debounce fires',
        );
      },
    );
  });
}
