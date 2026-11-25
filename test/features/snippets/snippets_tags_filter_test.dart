// Textbausteine carry tags and stars (#662): the rows show the tags, the
// filter popover narrows the list by favourites and by tag, a filter
// without hits offers its reset, and the editor has the notes' tag field.
library;

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/features/snippets/snippets_page.dart';

import '../../fixtures/test_helpers.dart';
import '../../test_helpers/pump_until.dart';

Finder _byId(String id) => find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.identifier == id,
);

Finder _row(String id) => find.byKey(ValueKey('snippets-row-$id'));

void _wide(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1400, 900);
  addTearDown(tester.view.reset);
}

Future<void> _seed(HistoryDatabase db) async {
  for (final (id, title) in [('a', 'Alpha'), ('b', 'Beta'), ('c', 'Gamma')]) {
    await db.upsertSnippet(
      id: id,
      title: title,
      body: 'Body of $title',
      createdAt: DateTime(2026),
    );
  }
  await db.setSnippetFavorite('a', favorite: true);
  final work = await db.createTag('work');
  final mail = await db.createTag('mail');
  await db.tagSnippet('a', work.id);
  await db.tagSnippet('b', work.id);
  await db.tagSnippet('b', mail.id);
}

Future<void> _pick(WidgetTester tester, String chipId) async {
  await tester.tap(_byId('snippets-filter-menu'));
  await tester.pumpAndSettle();
  await tester.tap(_byId(chipId));
  await tester.pumpAndSettle();
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pumpAndSettle();
}

void main() {
  late HistoryDatabase db;

  // Streams close with their last listener, without a pending timer.
  setUp(
    () => db = HistoryDatabase.forTesting(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    ),
  );
  tearDown(() => db.close());

  testWidgets('rows show their tags; tag and favourite filters narrow', (
    tester,
  ) async {
    _wide(tester);
    await tester.runAsync(() => _seed(db));
    await tester.pumpWidget(
      makeTestable(const SnippetsPage(), locale: const Locale('en'), db: db),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('snippets-tags-b')), findsOneWidget);
    expect(find.text('#mail'), findsOneWidget);
    expect(find.byKey(const ValueKey('snippets-tags-c')), findsNothing);

    final tags = await tester.runAsync(db.allTags);
    final mail = tags!.firstWhere((t) => t.name == 'mail');
    await _pick(tester, 'snippets-tag-filter-${mail.id}');
    expect(_row('b'), findsOneWidget);
    expect(_row('a'), findsNothing);
    expect(_row('c'), findsNothing);
    expect(_byId('snippets-filter-mark-tag-${mail.id}'), findsOneWidget);

    // Favourites and #mail together: nothing left, the reset brings all.
    await _pick(tester, 'snippets-filter-favourites');
    expect(_row('b'), findsNothing);
    expect(find.byKey(const ValueKey('snippets-filter-empty')), findsOneWidget);
    await tester.tap(find.text('Reset filter'));
    await tester.pumpAndSettle();
    for (final id in ['a', 'b', 'c']) {
      expect(_row(id), findsOneWidget, reason: id);
    }

    await _pick(tester, 'snippets-filter-favourites');
    expect(_row('a'), findsOneWidget);
    expect(_row('b'), findsNothing);
    expect(_byId('snippets-filter-mark-view'), findsOneWidget);
  });

  testWidgets('the editor tags the open snippet with the shared tags', (
    tester,
  ) async {
    _wide(tester);
    await tester.runAsync(() => _seed(db));
    await tester.pumpWidget(
      makeTestable(const SnippetsPage(), locale: const Locale('en'), db: db),
    );
    await tester.pumpAndSettle();

    await tester.tap(_row('c'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(_byId('snippets-editor-tags'), findsOneWidget);

    await tester.runAsync(() async {
      await db.tagSnippet('c', (await db.createTag('mail')).id);
    });
    await pumpUntil(
      tester,
      () => find.byKey(const ValueKey('snippets-tags-c')).evaluate().isNotEmpty,
      what: 'the new tag in the row of snippet c',
    );
    expect(find.byKey(const ValueKey('snippets-tags-c')), findsOneWidget);
  });
}
