// #1969: the learning log stayed empty because a transcript correction was
// only learned when the field lost focus inside the panel. Clicking the next
// recording or leaving the page saved the text but never learned from it.
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/features/history/widgets/history_detail_panel.dart';
import 'package:whispaste/services/replacements/correction_learning_service.dart';
import 'package:whispaste/services/replacements/correction_signal.dart';

import '../../fixtures/test_helpers.dart';

class _FakeSettingsNotifier extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => AppSettings.defaults;
}

class _RecordingLearningService extends CorrectionLearningService {
  final signals = <CorrectionSignal>[];

  @override
  Future<int> recordSignal(CorrectionSignal signal, HistoryDatabase db) async {
    signals.add(signal);
    return 0;
  }
}

void main() {
  Future<void> expectEditLearned(
    WidgetTester tester, {
    required bool switchEntry,
    required bool waitForAutosave,
  }) async {
    final db = HistoryDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    for (final id in ['a', 'b']) {
      await db.insertHistoryEntry(
        HistoryEntriesCompanion.insert(
          id: id,
          timestamp: DateTime(2026, 1, 1, 12),
          content: Value(id == 'a' ? 'teh meeting' : 'other'),
          title: Value(id),
        ),
      );
    }
    final rows = await db.select(db.historyEntries).get();
    final a = rows.firstWhere((e) => e.id == 'a');
    final b = rows.firstWhere((e) => e.id == 'b');
    final learning = _RecordingLearningService();

    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    Widget panel(HistoryEntry entry) => makeTestable(
      Scaffold(
        body: HistoryDetailPanel(
          entry: entry,
          isTrashView: false,
          onClose: () {},
          onCopy: () {},
          onPin: () {},
          onDelete: () {},
          onArchive: () {},
          onRestore: () {},
        ),
      ),
      db: db,
      locale: const Locale('en'),
      overrides: [
        settingsProvider.overrideWith(() => _FakeSettingsNotifier()),
        correctionLearningServiceProvider.overrideWithValue(learning),
      ],
    );
    await tester.pumpWidget(panel(a));
    await tester.pumpAndSettle();

    final editor = find.byWidgetPredicate(
      (w) => w is TextField && (w.controller?.text ?? '') == 'teh meeting',
    );
    await tester.tap(editor);
    await tester.enterText(editor, 'the meeting');
    await tester.pump();
    if (waitForAutosave) await tester.pump(const Duration(seconds: 5));

    // No blur inside the panel: the user clicks on and the panel changes.
    if (switchEntry) {
      await tester.pumpWidget(panel(b));
    } else {
      await tester.pumpWidget(const SizedBox.shrink());
    }
    await tester.pumpAndSettle();

    expect(learning.signals, hasLength(1));
    expect(learning.signals.single.sourceText, 'teh meeting');
    expect(learning.signals.single.targetText, 'the meeting');
    expect(learning.signals.single.source, CorrectionSignalSource.manualEdit);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
  }

  testWidgets('switching to the next recording learns the edit', (
    tester,
  ) async {
    await expectEditLearned(tester, switchEntry: true, waitForAutosave: false);
  });

  testWidgets('switching after the autosave learns the edit too', (
    tester,
  ) async {
    await expectEditLearned(tester, switchEntry: true, waitForAutosave: true);
  });

  testWidgets('leaving the page learns the edit', (tester) async {
    await expectEditLearned(tester, switchEntry: false, waitForAutosave: true);
  });
}
