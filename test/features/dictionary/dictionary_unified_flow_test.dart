/// The shared search must filter replacements and suggestions without rewriting any of
/// them, and keep the same keyboard/screen-reader contract on every desktop.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/sorting/list_sort.dart';
import 'package:whispaste/core/sorting/list_sort_preference.dart';
import 'package:whispaste/features/dictionary/dictionary_page.dart';
import 'package:whispaste/features/replacements/replacements_page.dart';
import 'package:whispaste/services/replacements/correction_learning_service.dart';
import 'package:whispaste/widgets/wp_search_field.dart';

import '../../fixtures/test_helpers.dart';

class _Settings extends SettingsNotifier {
  @override
  Future<AppSettings> build() async =>
      AppSettings.defaults.copyWith(customVocabulary: 'Alpha, Beta');
}

class _Sort extends ReplacementsSortNotifier {
  @override
  Future<ListSort> build() async => kReplacementsDefaultSort;
}

class _Replacements extends ReplacementsNotifier {
  @override
  Future<List<Replacement>> build() async => [
    Replacement(
      id: 'a',
      triggers: ['alpha'],
      replacement: 'First',
      createdAt: DateTime(2026),
    ),
    Replacement(
      id: 'b',
      triggers: ['beta'],
      replacement: 'Second',
      createdAt: DateTime(2026),
    ),
  ];
}

void main() {
  for (final locale in L10n.supportedLocales) {
    testWidgets(
      'one search preserves every store (${locale.languageCode})',
      (tester) async {
        await tester.pumpWidget(
          makeTestable(
            const DictionaryPage(),
            locale: locale,
            overrides: [
              settingsProvider.overrideWith(_Settings.new),
              replacementsProvider.overrideWith(_Replacements.new),
              // Search does not need a database or a loaded speech model.
              // Storage/order behavior is covered by the service/DB tests.
              replacementsSortProvider.overrideWith(_Sort.new),
              learnedTermsProvider.overrideWith((ref) async => {}),
              correctionLogProvider.overrideWith((ref) async => []),
              pendingCorrectionCandidatesProvider.overrideWith(
                (ref) async => const [
                  CorrectionCandidate(
                    id: 'ca',
                    sourceText: 'alfa',
                    targetText: 'Alpha',
                    occurrenceCount: 2,
                  ),
                  CorrectionCandidate(
                    id: 'cb',
                    sourceText: 'bta',
                    targetText: 'Beta',
                    occurrenceCount: 2,
                  ),
                ],
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(WpSearchField), findsOneWidget);
        final l10n = await L10n.delegate.load(locale);
        expect(
          find.bySemanticsLabel(
            RegExp(RegExp.escape(l10n.dictionaryTermsBarLabel)),
          ),
          findsOneWidget,
        );
        final field = find.byKey(const ValueKey('dictionary-terms-bar'));
        await tester.sendKeyDownEvent(primaryShortcutModifier);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
        await tester.sendKeyUpEvent(primaryShortcutModifier);
        await tester.pump();
        expect(
          tester
              .widget<EditableText>(
                find.descendant(of: field, matching: find.byType(EditableText)),
              )
              .focusNode
              .hasFocus,
          isTrue,
        );
        await tester.enterText(field, 'Alpha');
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('replacements-row-a')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('replacements-row-b')), findsNothing);
        expect(
          find.byKey(const ValueKey('dictionary-suggestion-term-ca')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('dictionary-suggestion-term-cb')),
          findsNothing,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('replacements-row-b')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('dictionary-suggestion-term-cb')),
          findsOneWidget,
        );
        final container = ProviderScope.containerOf(
          tester.element(find.byType(DictionaryPage)),
        );
        expect(
          container.read(settingsProvider).requireValue.stt.customVocabulary,
          'Alpha, Beta',
        );
        expect(
          container.read(replacementsProvider).requireValue.map((r) => r.id),
          ['a', 'b'],
        );
        expect(
          container
              .read(pendingCorrectionCandidatesProvider)
              .requireValue
              .map((c) => c.id),
          ['ca', 'cb'],
        );
        expect(tester.takeException(), isNull);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      }),
    );
  }
}
