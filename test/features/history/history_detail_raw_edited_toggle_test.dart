/// Widget test for the History detail panel's raw/edited view toggle
/// (Smart-Mode-v2 ticket 05).
///
/// An entry with a Smart-Mode-edited version shows a "Raw"/"Edited" toggle
/// next to the transcript; flipping it swaps the displayed transcript text
/// without ever touching the entry's raw content.
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/theme/theme.dart';
import 'package:whispaste/features/history/data/providers.dart';
import 'package:whispaste/features/history/history_page.dart';
import 'package:whispaste/features/history/widgets/highlighted_text.dart';
import 'package:whispaste/services/hardware_info_service.dart';
import 'package:whispaste/widgets/wp_text_field.dart';

late L10n l10n;

/// Local variant of `makeTestable` that takes an already-seeded
/// [HistoryDatabase] instead of creating an empty one — the toggle only
/// appears once an entry has a Smart-Mode-edited version, which has to be
/// present in the DB `historyDetailProvider` reads from, not just in the
/// list's own `historyEntriesProvider` stream.
Widget _pumpApp(HistoryDatabase db, HistoryEntry entry) {
  final theme = wpDarkTheme();

  return ProviderScope(
    overrides: [
      historyDatabaseProvider.overrideWith((ref) {
        ref.onDispose(db.close);
        return db;
      }),
      gpuInfoProvider.overrideWith(
        (ref) async => const GpuInfo(vendor: GpuVendor.none, name: 'Test'),
      ),
      historyEntriesProvider.overrideWith((ref) => Stream.value([entry])),
      archivedEntriesProvider.overrideWith((ref) => Stream.value(const [])),
      trashEntriesProvider.overrideWith((ref) => Stream.value(const [])),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      locale: const Locale('en'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: const MediaQuery(
        data: MediaQueryData(size: Size(1800, 900)),
        child: Scaffold(body: HistoryPage()),
      ),
    ),
  );
}

const _entryTitle = 'Smart Mode toggle test';
const _rawContent = 'raw text with um filler';
const _editedContent = 'Raw text, cleaned up.';

Future<HistoryEntry> _seedEntry(HistoryDatabase db) async {
  await db.insertHistoryEntry(
    HistoryEntriesCompanion.insert(
      id: 'toggle-1',
      timestamp: DateTime(2026, 1, 1, 10),
      content: const Value(_rawContent),
      title: const Value(_entryTitle),
    ),
  );
  await db.updateEntry(
    'toggle-1',
    const HistoryEntriesCompanion(
      smartModeEditedContent: Value(_editedContent),
    ),
  );
  return (await db.getEntry('toggle-1'))!;
}

/// The detail panel's tight-fit overflow at some widths is a pre-existing,
/// documented condition (same waiver as `history_transcript_material_test.dart`
/// and `history_markdown_shortcuts_test.dart`) — these tests assert the
/// toggle's behavior, not layout.
void _ignoreOverflowErrors() {
  final originalHandler = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    if (details.toString().contains('overflowed')) return;
    originalHandler?.call(details);
  };
  addTearDown(() => FlutterError.onError = originalHandler);
}

Future<void> _openDetail(WidgetTester tester, HistoryDatabase db) async {
  _ignoreOverflowErrors();
  final entry = await _seedEntry(db);

  await tester.pumpWidget(_pumpApp(db, entry));
  await tester.pumpAndSettle();

  await tester.tap(find.text(_entryTitle).first);
  await tester.pumpAndSettle();
}

/// Scoped to the detail panel: the list's own card also renders a content
/// preview via [HighlightedText], so an unscoped search can match twice.
Finder _transcriptText(String text) => find.descendant(
  of: find.byType(WpTextFieldSurface),
  matching: find.byWidgetPredicate(
    (widget) => widget is HighlightedText && widget.text == text,
  ),
);

void main() {
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  testWidgets('entry with an edited version defaults to showing raw text', (
    tester,
  ) async {
    final db = HistoryDatabase.forTesting(NativeDatabase.memory());
    await _openDetail(tester, db);

    expect(_transcriptText(_rawContent), findsOneWidget);
    expect(_transcriptText(_editedContent), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('tapping "Edited" swaps the displayed transcript', (
    tester,
  ) async {
    final db = HistoryDatabase.forTesting(NativeDatabase.memory());
    await _openDetail(tester, db);

    await tester.tap(find.text(l10n.historyViewEdited));
    await tester.pumpAndSettle();

    expect(_transcriptText(_editedContent), findsOneWidget);
    expect(_transcriptText(_rawContent), findsNothing);

    // Underlying raw content is untouched by viewing the edited version.
    final entry = await db.getEntry('toggle-1');
    expect(entry!.content, _rawContent);
    expect(entry.smartModeEditedContent, _editedContent);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('toggling back to "Raw" restores the raw transcript view', (
    tester,
  ) async {
    final db = HistoryDatabase.forTesting(NativeDatabase.memory());
    await _openDetail(tester, db);

    await tester.tap(find.text(l10n.historyViewEdited));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.historyViewRaw));
    await tester.pumpAndSettle();

    expect(_transcriptText(_rawContent), findsOneWidget);
    expect(_transcriptText(_editedContent), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('an entry without an edited version shows no raw/edited toggle', (
    tester,
  ) async {
    _ignoreOverflowErrors();
    final db = HistoryDatabase.forTesting(NativeDatabase.memory());
    await db.insertHistoryEntry(
      HistoryEntriesCompanion.insert(
        id: 'no-toggle-1',
        timestamp: DateTime(2026, 1, 1, 10),
        content: const Value(_rawContent),
        title: const Value('No preset applied yet'),
      ),
    );
    final entry = (await db.getEntry('no-toggle-1'))!;

    await tester.pumpWidget(_pumpApp(db, entry));
    await tester.pumpAndSettle();

    await tester.tap(find.text('No preset applied yet').first);
    await tester.pumpAndSettle();

    expect(find.text(l10n.historyViewEdited), findsNothing);
    expect(find.text(l10n.historyViewRaw), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
