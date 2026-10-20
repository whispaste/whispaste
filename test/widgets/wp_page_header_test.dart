import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/generated/wp_tokens.g.dart';
import 'package:whispaste/core/theme/theme.dart';
import 'package:whispaste/widgets/wp_page_header.dart';

import '../fixtures/test_helpers.dart';

void main() {
  testWidgets('title is the Bricolage page title at 28 px bold', (
    tester,
  ) async {
    await tester.pumpWidget(makeTestable(const WpPageHeader(title: 'Notes')));

    final style = tester.widget<Text>(find.text('Notes')).style!;
    expect(style.fontFamily, kWpDisplayFont);
    expect(style.fontSize, WpTypeScaleTokens.pageTitle);
    expect(style.fontWeight, FontWeight.w700);
  });

  testWidgets('title is announced as a heading', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(makeTestable(const WpPageHeader(title: 'Notes')));

    final node = tester.getSemantics(find.text('Notes'));
    expect(node.flagsCollection.isHeader, isTrue);
    handle.dispose();
  });

  testWidgets('trailing slot holds the page action', (tester) async {
    await tester.pumpWidget(
      makeTestable(
        WpPageHeader(
          title: 'Notes',
          trailing: IconButton(
            key: const ValueKey('notes-new'),
            icon: const Icon(Icons.add),
            onPressed: () {},
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('notes-new')), findsOneWidget);
  });

  testWidgets('without a trailing widget only the title is shown', (
    tester,
  ) async {
    await tester.pumpWidget(makeTestable(const WpPageHeader(title: 'Notes')));

    expect(find.byType(IconButton), findsNothing);
    expect(find.text('Notes'), findsOneWidget);
  });
}
