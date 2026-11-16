/// A text too long for a version is reported even when the snapshot happens
/// while the page is being left (#636): the notice moves to the app-wide slot.
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/data/note_version_limits.dart';
import 'package:whispaste/core/data/notes_providers.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/notes/data/note_asset_store.dart';
import 'package:whispaste/features/notes/data/notes_actions.dart';
import 'package:whispaste/features/notes/notes_page.dart';
import 'package:whispaste/widgets/wp_page_notice.dart';

import '../../fixtures/test_helpers.dart';

/// Reports every snapshot as too large without writing a huge text.
class _TooLargeActions extends NotesActions {
  _TooLargeActions(super.db);

  @override
  Future<NoteVersionOutcome> snapshot(
    String noteId, {
    required String? title,
    required String content,
  }) async => NoteVersionOutcome.tooLarge;
}

void main() {
  late Directory appData;
  late HistoryDatabase db;

  setUp(() {
    appData = Directory.systemTemp.createTempSync('wp636-leave-');
    db = HistoryDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
    if (appData.existsSync()) appData.deleteSync(recursive: true);
  });

  testWidgets('leaving the page with a pending too-large snapshot warns', (
    tester,
  ) async {
    final id = (await tester.runAsync(() => db.createNote()))!.id;
    await tester.runAsync(() => db.updateNoteContent(id, 'Long note'));
    final note = (await tester.runAsync(() => db.getNote(id)))!;
    final l10n = await L10n.delegate.load(const Locale('en'));
    late ProviderContainer container;
    final showPage = ValueNotifier<bool>(true);

    await tester.pumpWidget(
      makeTestable(
        ValueListenableBuilder<bool>(
          valueListenable: showPage,
          builder: (context, show, _) {
            container = ProviderScope.containerOf(context);
            return show ? const NotesPage() : const SizedBox();
          },
        ),
        db: db,
        overrides: [
          noteAssetStoreProvider.overrideWithValue(
            NoteAssetStore(appDataDirPath: appData.path),
          ),
          notesActionsProvider.overrideWithValue(_TooLargeActions(db)),
          notesProvider.overrideWith((ref) => Stream.value([note])),
          allNoteTagsProvider.overrideWith((ref) => Stream.value(const {})),
          noteTagsProvider.overrideWith(
            (ref, noteId) => Stream.value(const []),
          ),
        ],
        locale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Long note').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('notes-editor-body')),
        matching: find.byType(TextField),
      ),
      'Long note, edited',
    );
    await tester.pump();

    // Leave: the page is disposed with the idle snapshot still pending.
    showPage.value = false;
    await tester.pump();
    await tester.runAsync(() => notesPageLastTeardown);
    await tester.pump();

    final open = container.read(wpAppErrorsProvider);
    expect(open.map((n) => n.id), contains('notes-version-too-large'));
    expect(
      open.firstWhere((n) => n.id == 'notes-version-too-large').message,
      l10n.notesVersionNoteTooLarge,
    );
  });
}
