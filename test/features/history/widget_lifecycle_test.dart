/// Widget lifecycle safety tests for HistoryDetailPanel.
///
/// Verifies that async operations (_suggestTitle, _suggestTags, _process)
/// do not crash when the widget is deactivated or disposed before completion.
/// Covers FLUTTER_WHISPASTE-W, Y, Z fixes.
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/features/history/widgets/history_detail_panel.dart';
import 'package:whispaste/services/post_processing_service.dart';
import '../../fixtures/test_helpers.dart';

void main() {
  group('Widget lifecycle safety', () {
    late HistoryDatabase db;
    late HistoryEntry testEntry;

    setUp(() async {
      db = HistoryDatabase.forTesting(NativeDatabase.memory());

      // Seed a test entry
      await db.upsertEntry(
        HistoryEntriesCompanion.insert(
          id: 'lifecycle-test-1',
          timestamp: DateTime(2025, 6, 1, 12, 0),
          content: const Value('Test content for lifecycle safety'),
          title: const Value('Test Title'),
          model: const Value('whisper-small'),
          isLocal: const Value(true),
          durationSec: const Value(5.0),
        ),
      );

      testEntry = (await db.getEntry('lifecycle-test-1'))!;
    });

    tearDown(() async {
      await db.close();
    });

    testWidgets(
      '_isTextFieldFocused does not crash when widget is deactivated',
      (tester) async {
        // Setup: Render the detail panel
        await tester.pumpWidget(
          makeTestable(
            HistoryDetailPanel(
              entry: testEntry,
              isDark: true,
              onClose: () {},
              onCopy: () {},
              onPin: () {},
              onDelete: () {},
              onArchive: () {},
              onRestore: () {},
            ),
            overrides: [
              historyDatabaseProvider.overrideWith((ref) {
                ref.onDispose(db.close);
                return db;
              }),
            ],
          ),
        );
        await tester.pumpAndSettle();

        // Verify widget is rendered
        expect(find.text('Test Title'), findsOneWidget);

        // Trigger focus on a text field (title edit)
        await tester.tap(find.text('Test Title'));
        await tester.pump();

        // Deactivate widget by replacing it with an empty container
        await tester.pumpWidget(Container());
        await tester.pump();

        // Verify: No crash occurred
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('_suggestTitle does not crash after widget disposal', (
      tester,
    ) async {
      final fakePostProcessing = FakePostProcessingNotifier();

      // Setup: Render the detail panel
      await tester.pumpWidget(
        makeTestable(
          HistoryDetailPanel(
            entry: testEntry,
            isDark: true,
            onClose: () {},
            onCopy: () {},
            onPin: () {},
            onDelete: () {},
            onArchive: () {},
            onRestore: () {},
          ),
          overrides: [
            historyDatabaseProvider.overrideWith((ref) {
              ref.onDispose(db.close);
              return db;
            }),
            postProcessingProvider.overrideWith(() => fakePostProcessing),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Trigger async operation: tap the suggest title button
      final suggestButton = find.byIcon(Icons.auto_awesome);
      expect(suggestButton, findsOneWidget);
      await tester.tap(suggestButton);
      await tester.pump(); // Start async operation

      // Deactivate widget before async completes
      await tester.pumpWidget(Container());
      await tester.pump();

      // Complete async operation (fake notifier resolves after 100ms)
      await tester.pump(const Duration(milliseconds: 150));

      // Verify: No crash occurred
      expect(tester.takeException(), isNull);
    });

    testWidgets('_suggestTags does not crash after widget disposal', (
      tester,
    ) async {
      final fakePostProcessing = FakePostProcessingNotifier();

      // Setup: Render the detail panel
      await tester.pumpWidget(
        makeTestable(
          HistoryDetailPanel(
            entry: testEntry,
            isDark: true,
            onClose: () {},
            onCopy: () {},
            onPin: () {},
            onDelete: () {},
            onArchive: () {},
            onRestore: () {},
          ),
          overrides: [
            historyDatabaseProvider.overrideWith((ref) {
              ref.onDispose(db.close);
              return db;
            }),
            postProcessingProvider.overrideWith(() => fakePostProcessing),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Scroll down to find the AI Actions section
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -500),
      );
      await tester.pumpAndSettle();

      // Trigger async operation: tap the suggest tags button
      final suggestTagsButton = find.byIcon(LucideIcons.tag);
      expect(suggestTagsButton, findsOneWidget);
      await tester.tap(suggestTagsButton);
      await tester.pump(); // Start async operation

      // Deactivate widget before async completes
      await tester.pumpWidget(Container());
      await tester.pump();

      // Complete async operation
      await tester.pump(const Duration(milliseconds: 150));

      // Verify: No crash occurred
      expect(tester.takeException(), isNull);
    });

    testWidgets('_process (cleanup) does not crash after widget disposal', (
      tester,
    ) async {
      final fakePostProcessing = FakePostProcessingNotifier();

      // Setup: Render the detail panel
      await tester.pumpWidget(
        makeTestable(
          HistoryDetailPanel(
            entry: testEntry,
            isDark: true,
            onClose: () {},
            onCopy: () {},
            onPin: () {},
            onDelete: () {},
            onArchive: () {},
            onRestore: () {},
          ),
          overrides: [
            historyDatabaseProvider.overrideWith((ref) {
              ref.onDispose(db.close);
              return db;
            }),
            postProcessingProvider.overrideWith(() => fakePostProcessing),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Scroll down to find the AI Actions section
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -500),
      );
      await tester.pumpAndSettle();

      // Trigger async operation: tap the cleanup button
      final cleanupButton = find.byIcon(LucideIcons.sparkles);
      expect(cleanupButton, findsOneWidget);
      await tester.tap(cleanupButton);
      await tester.pump(); // Start async operation

      // Deactivate widget before async completes
      await tester.pumpWidget(Container());
      await tester.pump();

      // Complete async operation
      await tester.pump(const Duration(milliseconds: 150));

      // Verify: No crash occurred
      expect(tester.takeException(), isNull);
    });

    testWidgets('_process (translate) does not crash after widget disposal', (
      tester,
    ) async {
      final fakePostProcessing = FakePostProcessingNotifier();

      // Setup: Render the detail panel
      await tester.pumpWidget(
        makeTestable(
          HistoryDetailPanel(
            entry: testEntry,
            isDark: true,
            onClose: () {},
            onCopy: () {},
            onPin: () {},
            onDelete: () {},
            onArchive: () {},
            onRestore: () {},
          ),
          overrides: [
            historyDatabaseProvider.overrideWith((ref) {
              ref.onDispose(db.close);
              return db;
            }),
            postProcessingProvider.overrideWith(() => fakePostProcessing),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Scroll down to find the AI Actions section
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -500),
      );
      await tester.pumpAndSettle();

      // Trigger async operation: tap the translate button
      final translateButton = find.byIcon(LucideIcons.languages);
      expect(translateButton, findsOneWidget);
      await tester.tap(translateButton);
      await tester.pump(); // Start async operation (opens dialog)

      // Deactivate widget before async completes
      await tester.pumpWidget(Container());
      await tester.pump();

      // Complete async operation
      await tester.pump(const Duration(milliseconds: 150));

      // Verify: No crash occurred
      expect(tester.takeException(), isNull);
    });

    testWidgets('Multiple async operations can be cancelled safely', (
      tester,
    ) async {
      final fakePostProcessing = FakePostProcessingNotifier();

      // Setup: Render the detail panel
      await tester.pumpWidget(
        makeTestable(
          HistoryDetailPanel(
            entry: testEntry,
            isDark: true,
            onClose: () {},
            onCopy: () {},
            onPin: () {},
            onDelete: () {},
            onArchive: () {},
            onRestore: () {},
          ),
          overrides: [
            historyDatabaseProvider.overrideWith((ref) {
              ref.onDispose(db.close);
              return db;
            }),
            postProcessingProvider.overrideWith(() => fakePostProcessing),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Trigger title suggestion
      final suggestTitleButton = find.byIcon(Icons.auto_awesome);
      await tester.tap(suggestTitleButton);
      await tester.pump();

      // Scroll and trigger tag suggestion
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -500),
      );
      await tester.pumpAndSettle();
      final suggestTagsButton = find.byIcon(LucideIcons.tag);
      await tester.tap(suggestTagsButton);
      await tester.pump();

      // Deactivate widget while both operations are in flight
      await tester.pumpWidget(Container());
      await tester.pump();

      // Complete all async operations
      await tester.pump(const Duration(milliseconds: 200));

      // Verify: No crash occurred
      expect(tester.takeException(), isNull);
    });

    testWidgets('Context access after deactivation is safely guarded', (
      tester,
    ) async {
      final fakePostProcessing = FakePostProcessingNotifier();

      // Setup: Render the detail panel
      await tester.pumpWidget(
        makeTestable(
          HistoryDetailPanel(
            entry: testEntry,
            isDark: true,
            onClose: () {},
            onCopy: () {},
            onPin: () {},
            onDelete: () {},
            onArchive: () {},
            onRestore: () {},
          ),
          overrides: [
            historyDatabaseProvider.overrideWith((ref) {
              ref.onDispose(db.close);
              return db;
            }),
            postProcessingProvider.overrideWith(() => fakePostProcessing),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Trigger an operation that accesses context (L10n)
      final suggestButton = find.byIcon(Icons.auto_awesome);
      await tester.tap(suggestButton);
      await tester.pump();

      // Deactivate widget
      await tester.pumpWidget(Container());
      await tester.pump();

      // Complete async operation
      await tester.pump(const Duration(milliseconds: 150));

      // Verify: No "Looking up a deactivated widget's ancestor" error
      expect(tester.takeException(), isNull);
    });
  });
}

// ---------------------------------------------------------------------------
// Fake PostProcessingNotifier for testing
// ---------------------------------------------------------------------------

/// Fake implementation that simulates async operations with delays.
class FakePostProcessingNotifier extends PostProcessingNotifier {
  @override
  PostProcessingStatus build() => const PostProcessingStatus();

  @override
  Future<String> suggestTitle(String text) async {
    await Future.delayed(const Duration(milliseconds: 100));
    return 'Suggested Title';
  }

  @override
  Future<List<String>> suggestTags(String text) async {
    await Future.delayed(const Duration(milliseconds: 100));
    return ['tag1', 'tag2', 'tag3'];
  }

  @override
  Future<String> process(
    String text,
    PostProcessPreset preset, {
    String? targetLang,
  }) async {
    await Future.delayed(const Duration(milliseconds: 100));
    return 'Processed: $text';
  }
}
