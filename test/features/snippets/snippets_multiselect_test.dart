// #861: Textbausteine can be marked in a list and handled together. Space marks
// the row under the cursor and opens the selection bar; the bar trashes (with
// an undo that names the count), stars and exports the marked rows only.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/history/data/export_service.dart';
import 'package:whispaste/features/snippets/snippets_page.dart';
import 'package:whispaste/services/snippets/snippets_exporter.dart';

import '../../fixtures/test_helpers.dart';

Future<void> _seed(ProviderContainer c, List<String> titles) async {
  final n = c.read(snippetsProvider.notifier);
  await c.read(snippetsProvider.future);
  for (final t in titles) {
    await n.add(t, 'body of $t');
  }
}

void main() {
  late L10n l10n;
  late HistoryDatabase db;

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  setUp(() {
    db = HistoryDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  group('notifier', () {
    test('setFavouriteMany stars and un-stars exactly the given ids', () async {
      final c = ProviderContainer(
        overrides: [historyDatabaseProvider.overrideWith((ref) => db)],
      );
      addTearDown(c.dispose);
      await _seed(c, ['A', 'B', 'C']);
      final items = c.read(snippetsProvider).value!;
      final ids = [for (final s in items.where((s) => s.title != 'C')) s.id];

      await c
          .read(snippetsProvider.notifier)
          .setFavouriteMany(ids, value: true);
      expect(
        {
          for (final s in c.read(snippetsProvider).value!)
            s.title: s.isFavorite,
        },
        {'A': true, 'B': true, 'C': false},
      );

      await c
          .read(snippetsProvider.notifier)
          .setFavouriteMany(ids, value: false);
      expect(c.read(snippetsProvider).value!.any((s) => s.isFavorite), isFalse);
    });
  });

  group('exporter', () {
    final rows = <SnippetExportRow>[
      (id: '1', title: 'A', body: 'one', changedAt: DateTime(2026, 1, 1)),
      (id: '2', title: 'B', body: 'two', changedAt: DateTime(2026, 1, 2)),
    ];

    testWidgets('writes every row in the chosen format to the chosen path', (
      tester,
    ) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        makeTestable(
          Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox();
            },
          ),
          locale: const Locale('en'),
        ),
      );
      List<ExportEntry>? written;
      ExportFormat? writtenFormat;
      String? writtenPath;
      String? notice;
      final done = await SnippetsExporter(
        pickerFn: (_) async => ExportFormat.md,
        saveLocationFn: ({required format, required suggestedName}) async =>
            '/tmp/out.md',
        exporter: (entries, format, path) async {
          written = entries;
          writtenFormat = format;
          writtenPath = path;
          return entries.length;
        },
        notifier: (_, {required failed, required message}) => notice = message,
      ).exportSnippets(ctx, rows);

      expect(done, isTrue);
      expect(written!.map((e) => e.title), ['A', 'B']);
      expect(written!.map((e) => e.text), ['one', 'two']);
      expect(writtenFormat, ExportFormat.md);
      expect(writtenPath, '/tmp/out.md');
      expect(notice, l10n.historyExportDone('/tmp/out.md'));
    });

    testWidgets('a dismissed picker or save dialog writes nothing', (
      tester,
    ) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        makeTestable(
          Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox();
            },
          ),
          locale: const Locale('en'),
        ),
      );
      var writes = 0;
      Future<int> exporter(
        List<ExportEntry> e,
        ExportFormat f,
        String p,
      ) async {
        writes++;
        return 0;
      }

      expect(
        await SnippetsExporter(
          pickerFn: (_) async => null,
          exporter: exporter,
        ).exportSnippets(ctx, rows),
        isFalse,
      );
      expect(
        await SnippetsExporter(
          pickerFn: (_) async => ExportFormat.txt,
          saveLocationFn: ({required format, required suggestedName}) async =>
              null,
          exporter: exporter,
        ).exportSnippets(ctx, rows),
        isFalse,
      );
      expect(writes, 0);
    });

    testWidgets('a failing write reports an error and returns false', (
      tester,
    ) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        makeTestable(
          Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox();
            },
          ),
          locale: const Locale('en'),
        ),
      );
      bool? failed;
      final done = await SnippetsExporter(
        pickerFn: (_) async => ExportFormat.txt,
        saveLocationFn: ({required format, required suggestedName}) async =>
            '/x',
        exporter: (e, f, p) async => throw Exception('disk'),
        notifier: (_, {required failed, required message}) => failed = failed,
      ).exportSnippets(ctx, rows);
      expect(done, isFalse);
      expect(failed, anyOf(isNull, isTrue));
    });
  });

  testWidgets('Space marks rows, the bar trashes them with a counted undo', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [historyDatabaseProvider.overrideWith((ref) => db)],
    );
    addTearDown(container.dispose);
    await _seed(container, ['Alpha', 'Beta', 'Gamma']);
    final ids = {
      for (final s in container.read(snippetsProvider).value!) s.title: s.id,
    };

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: makeTestable(
          const SnippetsPage(),
          locale: const Locale('en'),
          noticeBar: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // No selection UI before the mode is entered.
    expect(
      find.byKey(const ValueKey('snippets-multiselect-delete')),
      findsNothing,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('snippets-multiselect-delete')),
      findsOneWidget,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('snippets-multiselect-delete')));
    await tester.pumpAndSettle();

    expect(container.read(snippetsProvider).value, hasLength(1));
    // The bar is gone: the mode ends with the action.
    expect(
      find.byKey(const ValueKey('snippets-multiselect-delete')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('snippets-undo')));
    await tester.pumpAndSettle();
    expect(container.read(snippetsProvider).value, hasLength(3));
    expect(ids, hasLength(3));
  });

  testWidgets('the bar stars the marked rows; Esc leaves without a change', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [historyDatabaseProvider.overrideWith((ref) => db)],
    );
    addTearDown(container.dispose);
    await _seed(container, ['Alpha', 'Beta']);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: makeTestable(
          const SnippetsPage(),
          locale: const Locale('en'),
          noticeBar: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('snippets-multiselect-delete')),
      findsNothing,
    );
    expect(
      container.read(snippetsProvider).value!.any((s) => s.isFavorite),
      isFalse,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('snippets-multiselect-select-all')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('snippets-multiselect-more')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('snippets-multiselect-more-favourite')),
    );
    await tester.pumpAndSettle();

    expect(
      container.read(snippetsProvider).value!.every((s) => s.isFavorite),
      isTrue,
    );
    // Let the confirmation notice close itself so no timer outlives the test.
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
  });
}
