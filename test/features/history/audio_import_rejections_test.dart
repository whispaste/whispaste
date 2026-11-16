/// Refused files in the import header: at most kHistoryInlineRows reasons
/// show inline, and only a longer list offers "Show all", which opens the
/// dialog with every reason.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/features/history/widgets/audio_import_panel.dart';
import 'package:whispaste/services/audio/import/audio_import_queue.dart';

import '../../fixtures/test_helpers.dart';

const _showAll = ValueKey('history-import-rejections-show-all');
const _dialogClose = ValueKey<String>('history-head-close');

void main() {
  Future<void> mountWith(WidgetTester tester, int refused) async {
    await tester.pumpWidget(
      makeTestable(
        const AudioImportPanel(),
        db: HistoryDatabase.forTesting(NativeDatabase.memory()),
        locale: const Locale('en'),
      ),
    );
    ProviderScope.containerOf(
      tester.element(find.byType(AudioImportPanel)),
    ).read(audioImportRejectionsProvider.notifier).set([
      for (var i = 0; i < refused; i++)
        ImportRejection(
          path: '/tmp/file-$i.docx',
          reason: ImportRejectionReason.unsupportedType,
        ),
    ]);
    await tester.pump();
  }

  testWidgets('two refusals fit inline: no show-all', (tester) async {
    await mountWith(tester, 2);
    expect(find.byKey(_showAll), findsNothing);
  });

  testWidgets('a third refusal moves the list behind show-all', (tester) async {
    await mountWith(tester, 3);
    expect(find.byKey(_showAll), findsOneWidget);

    await tester.tap(find.byKey(_showAll));
    await tester.pumpAndSettle();
    expect(find.byKey(_dialogClose), findsOneWidget);
  });
}
