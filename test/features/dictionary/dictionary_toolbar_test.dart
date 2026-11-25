// #1969: the dictionary head is the page family's toolbar, so its buttons
// stand apart with the shared gap like on Notes and Snippets.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/features/dictionary/dictionary_page.dart';
import 'package:whispaste/widgets/wp_collection_page.dart';

import '../../fixtures/test_helpers.dart';

class _FakeSettingsNotifier extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => AppSettings.defaults;
}

void main() {
  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      makeTestable(
        const DictionaryPage(),
        db: HistoryDatabase.forTesting(NativeDatabase.memory()),
        overrides: [settingsProvider.overrideWith(_FakeSettingsNotifier.new)],
        locale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the head is the shared collection toolbar', (tester) async {
    await pumpPage(tester);

    final toolbar = find.byType(WpCollectionToolbar);
    expect(toolbar, findsOneWidget);
    expect(
      find.descendant(
        of: toolbar,
        matching: find.byKey(const ValueKey('dictionary-more')),
      ),
      findsOneWidget,
    );
  });

  testWidgets('no two toolbar buttons touch', (tester) async {
    await pumpPage(tester);

    final buttons = [
      for (final e
          in find
              .descendant(
                of: find.byType(WpCollectionToolbar),
                matching: find.byWidgetPredicate(
                  (w) =>
                      w.key is ValueKey<String> &&
                      {
                        'dictionary-terms-add',
                        'dictionary-more',
                        'replacements-sort',
                      }.contains((w.key! as ValueKey<String>).value),
                ),
              )
              .evaluate())
        tester.getRect(find.byWidget(e.widget)),
    ]..sort((a, b) => a.left.compareTo(b.left));
    expect(buttons.length, greaterThanOrEqualTo(2));
    for (var i = 1; i < buttons.length; i++) {
      expect(
        buttons[i].left - buttons[i - 1].right,
        greaterThanOrEqualTo(WpCollectionToolbar.controlGap),
      );
    }
  });

  testWidgets('"often misspelled as" shows only for typed text', (
    tester,
  ) async {
    await pumpPage(tester);
    const toggle = ValueKey('dictionary-terms-misspelled-toggle');
    expect(find.byKey(toggle), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('dictionary-terms-bar')),
      'kubernets',
    );
    await tester.pumpAndSettle();
    // In the toolbar row, right of the search.
    expect(
      find.descendant(
        of: find.byType(WpCollectionToolbar),
        matching: find.byKey(toggle),
      ),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey('dictionary-terms-bar')),
      '',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(toggle), findsNothing);
  });
}
