// A failing correction-learning write must never break saving a transcript
// edit and must not raise an unhandled async error (issue #320).
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

class _ThrowingLearningService extends CorrectionLearningService {
  int calls = 0;

  @override
  Future<int> recordSignal(CorrectionSignal signal, HistoryDatabase db) async {
    calls++;
    throw StateError('learning store unavailable');
  }
}

const _content = 'teh meeting';

void main() {
  testWidgets(
    'a throwing recordSignal does not break saving a transcript edit',
    (tester) async {
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await db.insertHistoryEntry(
        HistoryEntriesCompanion.insert(
          id: 'learn-1',
          timestamp: DateTime(2026, 1, 1, 12),
          content: const Value(_content),
          title: const Value('Learn'),
        ),
      );
      final entry = (await db.select(db.historyEntries).get()).single;
      final learning = _ThrowingLearningService();

      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        makeTestable(
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
        ),
      );
      await tester.pumpAndSettle();

      // The transcript is written directly; no mode to open.
      final editor = find.byWidgetPredicate(
        (w) => w is TextField && (w.controller?.text ?? '') == _content,
      );
      expect(editor, findsOneWidget);
      await tester.enterText(editor, 'the meeting');
      await tester.pump();

      // Leaving the field ends the session, which flushes and learns.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();

      expect(learning.calls, 1);
      expect((await db.getEntry('learn-1'))!.content, 'the meeting');
      expect(tester.takeException(), isNull);

      await tester.pump(const Duration(seconds: 10));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
