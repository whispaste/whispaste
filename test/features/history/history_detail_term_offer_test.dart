// Correcting a word in a history entry offers it for the dictionary in one
// step (issue #587).
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/features/dictionary/role_terms.dart';
import 'package:whispaste/features/history/widgets/history_detail_panel.dart';

import '../../fixtures/test_helpers.dart';

class _FakeSettingsNotifier extends SettingsNotifier {
  _FakeSettingsNotifier(this.vocabulary);

  final String vocabulary;

  @override
  Future<AppSettings> build() async =>
      AppSettings.defaults.copyWith(customVocabulary: vocabulary);
}

const _content = 'we use Cubernetes daily';

Future<ProviderContainer> _openCorrectedEntry(
  WidgetTester tester, {
  required String vocabulary,
  required String corrected,
}) async {
  final db = HistoryDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);
  await db.insertHistoryEntry(
    HistoryEntriesCompanion.insert(
      id: 'term-1',
      timestamp: DateTime(2026, 1, 1, 12),
      content: const Value(_content),
      title: const Value('Term'),
    ),
  );
  final entry = (await db.select(db.historyEntries).get()).single;

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
        settingsProvider.overrideWith(() => _FakeSettingsNotifier(vocabulary)),
      ],
    ),
  );
  await tester.pumpAndSettle();

  final editor = find.byWidgetPredicate(
    (w) => w is TextField && (w.controller?.text ?? '') == _content,
  );
  expect(editor, findsOneWidget);
  await tester.enterText(editor, corrected);
  await tester.pump();
  // Leaving the field ends the session; the offer follows.
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(
    tester.element(find.byType(HistoryDetailPanel)),
  );
}

Future<void> _tearDown(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 10));
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

void main() {
  const offerKey = ValueKey('page-notice-add-term');
  const actionId = 'history-notice-add-term';

  testWidgets('a corrected word is added to the dictionary in one step', (
    tester,
  ) async {
    final container = await _openCorrectedEntry(
      tester,
      vocabulary: 'Acme',
      corrected: 'we use Kubernetes daily',
    );
    expect(find.byKey(offerKey), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey(actionId)));
    await tester.pumpAndSettle();

    final vocabulary = container.read(settingsProvider).value!.stt;
    expect(vocabularyTerms(vocabulary.customVocabulary), [
      'Acme',
      'Kubernetes',
    ]);
    expect(find.byKey(const ValueKey(actionId)), findsNothing);
    await _tearDown(tester);
  });

  testWidgets('a word the dictionary already holds is not offered again', (
    tester,
  ) async {
    await _openCorrectedEntry(
      tester,
      vocabulary: 'kubernetes',
      corrected: 'we use Kubernetes daily',
    );
    expect(find.byKey(offerKey), findsNothing);
    await _tearDown(tester);
  });
}
