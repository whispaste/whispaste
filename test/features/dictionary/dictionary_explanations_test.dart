/// #621: the Wörterbuch says each thing once. Covers what the explanation
/// pass changed in behaviour: the tab count, the jump to a tab, the offer to
/// create a term from a search with no hit, and the engine hint that only
/// shows when terms change nothing.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/dictionary/dictionary_tab_target.dart';
import 'package:whispaste/features/dictionary/dictionary_page.dart';
import 'package:whispaste/features/replacements/replacements_page.dart';
import 'package:whispaste/features/settings/search/settings_search_entry.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/services/replacements/correction_learning_service.dart';
import 'package:whispaste/widgets/wp_button.dart';

import '../../fixtures/test_helpers.dart';

class _Settings extends SettingsNotifier {
  _Settings(this._settings);

  AppSettings _settings;
  final List<AppSettings> updates = <AppSettings>[];

  @override
  Future<AppSettings> build() async => _settings;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    _settings = updater(state.value ?? _settings);
    updates.add(_settings);
    state = AsyncData(_settings);
  }
}

late L10n l10n;

Finder _button(String testId) =>
    find.byWidgetPredicate((w) => w is WpButton && w.testId == testId);

void main() {
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  Future<(_Settings, ProviderContainer)> pump(
    WidgetTester tester, {
    AppSettings? settings,
    List<CorrectionCandidate> candidates = const [],
  }) async {
    final notifier = _Settings(settings ?? AppSettings.defaults);
    await tester.pumpWidget(
      makeTestable(
        const DictionaryPage(),
        db: HistoryDatabase.forTesting(NativeDatabase.memory()),
        overrides: [
          settingsProvider.overrideWith(() => notifier),
          pendingCorrectionCandidatesProvider.overrideWith(
            (ref) async => candidates,
          ),
        ],
        locale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(DictionaryPage)),
    );
    return (notifier, container);
  }

  testWidgets('the engine hint is silent while terms work', (tester) async {
    await pump(tester);

    // The engine hint is silent while terms work.
    expect(
      find.byKey(const ValueKey('dictionary-terms-no-hints')),
      findsNothing,
    );
  });

  testWidgets('the suggestions tab shows how many are open', (tester) async {
    const candidate = CorrectionCandidate(
      id: 'c1',
      sourceText: 'kubernets',
      targetText: 'Kubernetes',
      occurrenceCount: 2,
    );
    await pump(tester, candidates: [candidate]);

    expect(find.text(l10n.dictionaryTabSuggestionsCount(1)), findsOneWidget);
    expect(find.text(l10n.dictionaryTabSuggestions), findsNothing);
  });

  testWidgets('a search without a hit offers to create it as a term', (
    tester,
  ) async {
    final (settings, _) = await pump(
      tester,
      settings: AppSettings.defaults.copyWith(customVocabulary: 'Alice'),
    );

    await tester.enterText(
      find.byKey(const ValueKey('dictionary-terms-bar')),
      'Zebra',
    );
    await tester.pumpAndSettle();
    expect(find.text(l10n.dictionaryTermsNoMatch('Zebra')), findsOneWidget);

    await tester.tap(_button('dictionary-terms-create-from-search'));
    await tester.pumpAndSettle();

    expect(settings.updates.single.stt.customVocabulary, contains('Zebra'));
  });

  testWidgets('an engine without term hints says so and offers a replacement', (
    tester,
  ) async {
    await pump(
      tester,
      settings: AppSettings.defaults.copyWithSections(
        stt: AppSettings.defaults.stt.copyWith(
          engine: OnDeviceEngine.parakeet.value,
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey('dictionary-terms-no-hints')),
      findsOneWidget,
    );

    await tester.tap(_button('dictionary-terms-as-replacement'));
    await tester.pumpAndSettle();

    // The replacements tab is open with the new-replacement dialog on top.
    expect(find.byKey(const ValueKey('replacements-save')), findsOneWidget);
  });

  testWidgets('a jump from elsewhere opens the named tab once', (tester) async {
    final (_, container) = await pump(tester);

    container
        .read(dictionaryTabTargetProvider.notifier)
        .set(DictionaryTab.suggestions);
    await tester.pumpAndSettle();

    expect(find.text(l10n.dictionarySuggestionsEmpty), findsOneWidget);
    expect(container.read(dictionaryTabTargetProvider), isNull);
  });

  test('search rows open the tab they name', () {
    expect(dictionaryTabForRow('speech-vocabulary'), DictionaryTab.terms);
    expect(
      dictionaryTabForRow('dictionary-replacements'),
      DictionaryTab.replacements,
    );
    expect(
      dictionaryTabForRow('dictionary-suggestions'),
      DictionaryTab.suggestions,
    );
  });
}
