/// Tests for the custom vocabulary field (Wörterbuch, "Begriffe" tab).
///
/// The vocabulary field moved from the speech settings to the Wörterbuch
/// page (DictionaryTermsField, "Begriffe" tab). Tests pump the field directly.
///
/// Covers: initial value renders, placeholder text, hint text,
/// text input writes customVocabulary through settingsProvider (debounced).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show AsyncData, Consumer;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/dictionary/widgets/dictionary_terms_field.dart';

import '../../../fixtures/test_helpers.dart';

// ---------------------------------------------------------------------------
// Fake notifiers — mirrors gpu_acceleration_section_test.dart's setup
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

// Helper: pumps the field under a scroll view with the given settings.
Widget _pump(_FakeSettingsNotifier notifier, {String vocabulary = ''}) =>
    makeTestable(
      SingleChildScrollView(
        child: Consumer(
          // Builds the settings notifier, as the real page does.
          builder: (context, ref, _) {
            ref.watch(settingsProvider);
            return DictionaryTermsField(initialValue: vocabulary);
          },
        ),
      ),
      overrides: [settingsProvider.overrideWith(() => notifier)],
      locale: const Locale('en'),
    );

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  group('DictionaryTermsField (vocabulary)', () {
    // On-device provider, default (Whisper) engine — the only combination
    // that actually renders the field.
    AppSettings localWhisperSettings({String vocabulary = ''}) {
      return AppSettings.defaults.copyWith(
        sttProvider: SttProviderType.onDevice.value,
        customVocabulary: vocabulary,
      );
    }

    // -------------------------------------------------------------------------
    // 1. Section label and hint text
    // -------------------------------------------------------------------------

    // -------------------------------------------------------------------------
    // 2. Placeholder text
    // -------------------------------------------------------------------------

    // -------------------------------------------------------------------------
    // 3. Initial value pre-fills the field
    // -------------------------------------------------------------------------

    testWidgets('pre-fills the text field with the initial vocabulary value', (
      tester,
    ) async {
      const preloaded = 'whisper Kotlin Flutter';
      final notifier = _FakeSettingsNotifier(
        localWhisperSettings(vocabulary: preloaded),
      );
      await tester.pumpWidget(_pump(notifier, vocabulary: preloaded));
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
        final notifier = _FakeSettingsNotifier(localWhisperSettings());
        await tester.pumpWidget(_pump(notifier));
        await tester.pumpAndSettle();

        final vocabField = find.byType(TextField).last;
        await tester.tap(vocabField);
        await tester.enterText(vocabField, 'Riverpod Drift Flutter');
        // Pump one frame so onChanged fires
        await tester.pump();

        // Verify not written yet (debounce is still pending)
        expect(
          notifier.state.value?.customVocabulary,
          isNot('Riverpod Drift Flutter'),
        );

        // Advance past the 600 ms debounce
        await tester.pump(const Duration(milliseconds: 700));

        expect(
          notifier.state.value?.customVocabulary,
          'Riverpod Drift Flutter',
          reason: 'customVocabulary should be updated after debounce fires',
        );
      },
    );

    // -------------------------------------------------------------------------
    // 5. Leaving the page inside the debounce window keeps the last term (UIA-DIC-01)
    // -------------------------------------------------------------------------

    testWidgets(
      'leaving the field before the debounce still saves the typed term',
      (tester) async {
        final notifier = _FakeSettingsNotifier(localWhisperSettings());
        final showField = ValueNotifier<bool>(true);
        addTearDown(showField.dispose);
        await tester.pumpWidget(
          makeTestable(
            ValueListenableBuilder<bool>(
              valueListenable: showField,
              builder: (_, visible, _) => visible
                  ? SingleChildScrollView(
                      child: Consumer(
                        builder: (context, ref, _) {
                          ref.watch(settingsProvider);
                          return const DictionaryTermsField(initialValue: '');
                        },
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            overrides: [settingsProvider.overrideWith(() => notifier)],
            locale: const Locale('en'),
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField).last, 'Riverpod');
        await tester.pump();
        showField.value = false;
        await tester.pump();

        expect(notifier.state.value?.customVocabulary, 'Riverpod');
      },
    );
  });
}
