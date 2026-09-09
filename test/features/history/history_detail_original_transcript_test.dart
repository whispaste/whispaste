/// Widget test for the History detail panel's original-transcript
/// disclosure and target-app/character-count metadata (ticket 12).
///
/// The original (pre-Smart-Mode/pre-Replacements) transcript is only
/// offered as a collapsed disclosure when it was captured *and* actually
/// differs from the final [HistoryEntry.content] — no redundant display
/// when the two are identical or no original was ever captured.
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/theme/theme.dart';
import 'package:whispaste/features/history/data/providers.dart';
import 'package:whispaste/features/history/history_page.dart';
import 'package:whispaste/services/hardware_info_service.dart';

late L10n l10n;

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

/// Same waiver as `history_detail_raw_edited_toggle_test.dart` — these tests
/// assert visibility/content, not layout.
void _ignoreOverflowErrors() {
  final originalHandler = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    if (details.toString().contains('overflowed')) return;
    originalHandler?.call(details);
  };
  addTearDown(() => FlutterError.onError = originalHandler);
}

Future<void> _openDetail(
  WidgetTester tester,
  HistoryDatabase db,
  HistoryEntry entry,
  String title,
) async {
  _ignoreOverflowErrors();
  await tester.pumpWidget(_pumpApp(db, entry));
  await tester.pumpAndSettle();

  await tester.tap(find.text(title).first);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  testWidgets(
    'entry whose original differs from the final text shows the disclosure, '
    'collapsed by default',
    (tester) async {
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      await db.insertHistoryEntry(
        HistoryEntriesCompanion.insert(
          id: 'diff-1',
          timestamp: DateTime(2026, 1, 1, 10),
          content: const Value('Cleaned up final text.'),
          title: const Value('Diff entry'),
          originalTranscript: const Value('uh original text with um filler'),
        ),
      );
      final entry = (await db.getEntry('diff-1'))!;

      await _openDetail(tester, db, entry, 'Diff entry');

      expect(find.text(l10n.historyShowOriginalTranscript), findsOneWidget);
      // Collapsed: the original text is not in the tree yet.
      expect(find.text('uh original text with um filler'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('tapping the disclosure reveals the original transcript text', (
    tester,
  ) async {
    final db = HistoryDatabase.forTesting(NativeDatabase.memory());
    await db.insertHistoryEntry(
      HistoryEntriesCompanion.insert(
        id: 'diff-2',
        timestamp: DateTime(2026, 1, 1, 10),
        content: const Value('Cleaned up final text.'),
        title: const Value('Diff entry 2'),
        originalTranscript: const Value('uh original text with um filler'),
      ),
    );
    final entry = (await db.getEntry('diff-2'))!;

    await _openDetail(tester, db, entry, 'Diff entry 2');

    await tester.tap(find.text(l10n.historyShowOriginalTranscript));
    await tester.pumpAndSettle();

    expect(find.text('uh original text with um filler'), findsOneWidget);
    expect(find.text(l10n.historyHideOriginalTranscript), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'entry whose original equals the final text shows no disclosure',
    (tester) async {
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      const same = 'Identical original and final text.';
      await db.insertHistoryEntry(
        HistoryEntriesCompanion.insert(
          id: 'same-1',
          timestamp: DateTime(2026, 1, 1, 10),
          content: const Value(same),
          title: const Value('Same entry'),
          originalTranscript: const Value(same),
        ),
      );
      final entry = (await db.getEntry('same-1'))!;

      await _openDetail(tester, db, entry, 'Same entry');

      expect(find.text(l10n.historyShowOriginalTranscript), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('entry with no captured original shows no disclosure', (
    tester,
  ) async {
    final db = HistoryDatabase.forTesting(NativeDatabase.memory());
    await db.insertHistoryEntry(
      HistoryEntriesCompanion.insert(
        id: 'none-1',
        timestamp: DateTime(2026, 1, 1, 10),
        content: const Value('Just some text.'),
        title: const Value('No original entry'),
      ),
    );
    final entry = (await db.getEntry('none-1'))!;

    await _openDetail(tester, db, entry, 'No original entry');

    expect(find.text(l10n.historyShowOriginalTranscript), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('metadata row shows a character-count chip and, when captured, a '
      'target-app chip', (tester) async {
    final db = HistoryDatabase.forTesting(NativeDatabase.memory());
    const content = 'Twelve chars';
    await db.insertHistoryEntry(
      HistoryEntriesCompanion.insert(
        id: 'meta-1',
        timestamp: DateTime(2026, 1, 1, 10),
        content: const Value(content),
        title: const Value('Meta entry'),
        targetApp: const Value('com.microsoft.VSCode'),
      ),
    );
    final entry = (await db.getEntry('meta-1'))!;

    await _openDetail(tester, db, entry, 'Meta entry');

    expect(
      find.text(l10n.historyCharacterCount(content.length)),
      findsOneWidget,
    );
    expect(find.text('VSCode'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('metadata row shows no target-app chip when none was captured', (
    tester,
  ) async {
    final db = HistoryDatabase.forTesting(NativeDatabase.memory());
    await db.insertHistoryEntry(
      HistoryEntriesCompanion.insert(
        id: 'meta-2',
        timestamp: DateTime(2026, 1, 1, 10),
        content: const Value('No target app here'),
        title: const Value('No target entry'),
      ),
    );
    final entry = (await db.getEntry('meta-2'))!;

    await _openDetail(tester, db, entry, 'No target entry');

    expect(find.byIcon(LucideIcons.appWindow), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
