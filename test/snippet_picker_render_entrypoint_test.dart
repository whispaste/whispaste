/// Widget tests for [SnippetPickerBody]'s search-filter ranking.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/services/snippet_picker/snippet_picker_render_channel.dart';
import 'package:whispaste/snippet_picker_render_entrypoint.dart';

void main() {
  Future<void> pumpBody(
    WidgetTester tester,
    List<SnippetPickerRenderItem> items,
  ) async {
    final l10n = await L10n.delegate.load(const Locale('en'));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: SnippetPickerBody(
            items: items,
            showGeneration: 0,
            visible: true,
            searchController: TextEditingController(),
            l10n: l10n,
            onSelect: (_) {},
            onCancel: () {},
          ),
        ),
      ),
    );
    // Not pumpAndSettle: the panel's liquid-glass specular streak drifts on
    // a `repeat()`-ing AnimationController, which never settles.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets(
    'a query matching a snippet title ranks it above a snippet whose title '
    'does not match but whose body happens to contain the query (reported: '
    '"impl" ranked "Debugging" above "Implementierung")',
    (tester) async {
      await pumpBody(tester, const [
        SnippetPickerRenderItem(
          id: '1',
          title: 'Debugging',
          body: '## Ziel Diagnostiziere und behebe den impl bug',
        ),
        SnippetPickerRenderItem(
          id: '2',
          title: 'Implementierung',
          body: '## Ziel Implementiere das vom User beschriebene Feature',
        ),
      ]);

      await tester.enterText(find.byType(TextField), 'impl');
      await tester.pump();

      final titleFinder = find.text('Implementierung');
      final debuggingFinder = find.text('Debugging');
      expect(titleFinder, findsOneWidget);
      expect(debuggingFinder, findsOneWidget);

      final implementierungY = tester.getTopLeft(titleFinder).dy;
      final debuggingY = tester.getTopLeft(debuggingFinder).dy;
      expect(
        implementierungY,
        lessThan(debuggingY),
        reason:
            'title match must rank above a body-only match for the same query',
      );
    },
  );

  testWidgets(
    'a title starting with the query ranks above a title merely containing it',
    (tester) async {
      await pumpBody(tester, const [
        SnippetPickerRenderItem(
          id: '1',
          title: 'Re-Implementierung',
          body: 'body one',
        ),
        SnippetPickerRenderItem(
          id: '2',
          title: 'Implementierung',
          body: 'body two',
        ),
      ]);

      await tester.enterText(find.byType(TextField), 'Impl');
      await tester.pump();

      final prefixMatchY = tester.getTopLeft(find.text('Implementierung')).dy;
      final containsMatchY = tester
          .getTopLeft(find.text('Re-Implementierung'))
          .dy;
      expect(prefixMatchY, lessThan(containsMatchY));
    },
  );
}
