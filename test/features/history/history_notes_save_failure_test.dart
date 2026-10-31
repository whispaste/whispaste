// UIA-HIS-05: a note that fails to save stays in the input and the user is
// told, instead of the input being cleared as if the note were stored.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/history/widgets/history_notes_section.dart';

import '../../fixtures/test_helpers.dart';

class _FailingNotesDb extends HistoryDatabase {
  _FailingNotesDb() : super.forTesting(NativeDatabase.memory());

  @override
  Future<void> upsertNote(EntryNotesCompanion note) async {
    throw StateError('database is locked');
  }
}

void main() {
  late L10n l10n;

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  testWidgets('a note that fails to save stays in the input and reports the '
      'error (UIA-HIS-05)', (tester) async {
    final db = _FailingNotesDb();
    addTearDown(db.close);
    await tester.pumpWidget(
      makeTestable(
        const HistoryNotesSection(entryId: 'notes-failure'),
        locale: const Locale('en'),
        db: db,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.historyAddNote));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Call Anna');
    await tester.tap(find.byTooltip(l10n.actionSave).first);
    await tester.pumpAndSettle();

    expect(find.text('Call Anna'), findsOneWidget);
    expect(find.text(l10n.historyWriteFailedToast), findsOneWidget);

    // Let the toast dismiss before the tree is torn down.
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
