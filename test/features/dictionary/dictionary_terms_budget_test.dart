/// The terms list shows where the active recognition stops using the terms
/// (#622) and lets a term move up by keyboard-reachable button.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/features/dictionary/terms_budget_provider.dart';
import 'package:whispaste/features/dictionary/widgets/dictionary_terms_list.dart';

import '../../fixtures/test_helpers.dart';

class _Settings extends SettingsNotifier {
  @override
  Future<AppSettings> build() async =>
      AppSettings.defaults.copyWith(customVocabulary: 'alpha, beta, gamma');
}

void main() {
  Future<ProviderContainer> pump(WidgetTester tester, int? leftOutFrom) async {
    final db = HistoryDatabase.forTesting(NativeDatabase.memory());
    await tester.pumpWidget(
      makeTestable(
        const SingleChildScrollView(child: DictionaryTermsList()),
        db: db,
        overrides: [
          settingsProvider.overrideWith(_Settings.new),
          termsLeftOutFromProvider.overrideWith((ref) async => leftOutFrom),
        ],
        locale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
      tester.element(find.byType(DictionaryTermsList)),
    );
  }

  testWidgets('the divider sits in front of the first term left out', (
    tester,
  ) async {
    await pump(tester, 2);

    expect(
      find.byKey(const ValueKey('dictionary-terms-left-out')),
      findsOneWidget,
    );
  });

  testWidgets('no divider when the recognition uses every term', (
    tester,
  ) async {
    await pump(tester, null);
    expect(
      find.byKey(const ValueKey('dictionary-terms-left-out')),
      findsNothing,
    );
  });

  testWidgets('moving a term up reorders the stored list', (tester) async {
    final container = await pump(tester, null);

    await tester.tap(find.byKey(const ValueKey('dictionary-term-move-up-2')));
    await tester.pumpAndSettle();

    expect(
      container.read(settingsProvider).value?.stt.customVocabulary,
      'alpha, gamma, beta',
    );
  });

  testWidgets('the first term cannot move up', (tester) async {
    final container = await pump(tester, null);

    await tester.tap(
      find.byKey(const ValueKey('dictionary-term-move-up-0')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(
      container.read(settingsProvider).value?.stt.customVocabulary,
      'alpha, beta, gamma',
    );
  });
}
