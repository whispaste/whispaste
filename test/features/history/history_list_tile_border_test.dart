import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/features/history/widgets/history_list_tile.dart';
import '../../fixtures/test_helpers.dart';

void main() {
  group('HistoryListTile border', () {
    testWidgets('selected tile renders without borderRadius+Border error', (
      tester,
    ) async {
      // Create a test entry
      final entry = HistoryEntry(
        id: '1',
        content: 'Test content',
        title: 'Test title',
        timestamp: DateTime(2026, 4, 14),
        durationSec: 30.0,
        processingDurationSec: 1.0,
        language: 'en',
        languageHint: '',
        tags: '[]',
        pinned: false,
        source: 'microphone',
        model: 'whisper-base',
        isLocal: true,
        costUsd: 0.0,
        archived: false,
        deletedAt: null,
        titleEdited: false,
      );

      await tester.pumpWidget(
        makeTestable(
          HistoryEntryRow(
            entry: entry,
            isDark: true,
            isSelected: true, // Selected state triggers the border
            onTap: () {},
            onCopy: () {},
            onPin: () {},
            onDelete: () {},
          ),
        ),
      );

      // Verify no FlutterError was thrown
      expect(tester.takeException(), isNull);

      // Verify widget rendered
      expect(find.text('Test title'), findsOneWidget);
    });

    testWidgets('unselected tile renders correctly', (tester) async {
      final entry = HistoryEntry(
        id: '2',
        content: 'Test content',
        title: 'Unselected',
        timestamp: DateTime(2026, 4, 14),
        durationSec: 10.0,
        processingDurationSec: 0.5,
        language: 'de',
        languageHint: '',
        tags: '[]',
        pinned: false,
        source: 'microphone',
        model: 'whisper-base',
        isLocal: true,
        costUsd: 0.0,
        archived: false,
        deletedAt: null,
        titleEdited: false,
      );

      await tester.pumpWidget(
        makeTestable(
          HistoryEntryRow(
            entry: entry,
            isDark: true,
            isSelected: false,
            onTap: () {},
            onCopy: () {},
            onPin: () {},
            onDelete: () {},
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Unselected'), findsOneWidget);
    });

    testWidgets('selected tile shows uniform border with borderRadius', (
      tester,
    ) async {
      final entry = HistoryEntry(
        id: '3',
        content: 'Test',
        title: 'Border test',
        timestamp: DateTime(2026, 4, 14),
        durationSec: 5.0,
        processingDurationSec: 0.2,
        language: 'en',
        languageHint: '',
        tags: '[]',
        pinned: false,
        source: 'microphone',
        model: 'whisper-tiny',
        isLocal: true,
        costUsd: 0.0,
        archived: false,
        deletedAt: null,
        titleEdited: false,
      );

      await tester.pumpWidget(
        makeTestable(
          HistoryEntryRow(
            entry: entry,
            isDark: true,
            isSelected: true,
            onTap: () {},
            onCopy: () {},
            onPin: () {},
            onDelete: () {},
          ),
        ),
      );

      // Verify rendering succeeded (no FlutterError about borderRadius)
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
