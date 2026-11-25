/// Hand-over tests for the Notes multi-select (#655): each batch action is
/// reached by test IDs and keyboard only, hands the ticked notes to
/// [NotesActions] in one call, and one undo takes the whole batch back.
/// Pattern of the snippet hand-over tests (#861).
library;

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/data/notes_providers.dart';
import 'package:whispaste/features/notes/data/notes_actions.dart';
import 'package:whispaste/features/notes/notes_page.dart';
import 'package:whispaste/widgets/wp_collection_page.dart';
import 'package:whispaste/widgets/wp_icon_button.dart';
import 'package:whispaste/widgets/wp_multi_select_bar.dart';
import 'package:whispaste/widgets/wp_notice_bar.dart';

import '../../fixtures/test_helpers.dart';

/// Records every batch call instead of touching the database; the list is a
/// static `Stream.value` fixture, so the calls are what the test can see.
class _BulkActions extends NotesActions {
  _BulkActions(super.db, this.notes);

  final List<Note> notes;
  final calls = <String>[];

  @override
  Future<Note?> getNote(String noteId) async =>
      notes.where((n) => n.id == noteId).firstOrNull;

  @override
  Future<int> moveManyToTrash(List<String> noteIds) async {
    calls.add('trash:${noteIds.join(',')}');
    return noteIds.length;
  }

  @override
  Future<int> restoreMany(List<String> noteIds) async {
    calls.add('restore:${noteIds.join(',')}');
    return noteIds.length;
  }

  @override
  Future<int> setPinnedMany(
    List<String> noteIds, {
    required bool pinned,
  }) async {
    calls.add('pin:$pinned:${noteIds.join(',')}');
    return noteIds.length;
  }

  @override
  Future<({String tagId, List<String> added})?> addTagToMany(
    List<String> noteIds,
    String tagName,
  ) async {
    calls.add('tag:$tagName:${noteIds.join(',')}');
    return (tagId: 't1', added: noteIds);
  }

  @override
  Future<void> removeTagFromMany(List<String> noteIds, String tagId) async {
    calls.add('untag:$tagId:${noteIds.join(',')}');
  }

  @override
  Future<Note?> merge(List<String> noteIds) async {
    calls.add('merge:${noteIds.join(',')}');
    return _note('m', 'Merged');
  }

  @override
  Future<void> undoMerge(String mergedId, List<String> sourceIds) async {
    calls.add('unmerge:$mergedId:${sourceIds.join(',')}');
  }
}

Note _note(String id, String content, {bool pinned = false}) {
  final t = DateTime(2025, 6, 1);
  return Note(
    archived: false,
    id: id,
    content: content,
    pinned: pinned,
    isQuickNote: false,
    deletedAt: null,
    createdAt: t,
    updatedAt: t,
  );
}

final _notes = [
  _note('n1', 'First note'),
  _note('n2', 'Second note'),
  _note('n3', 'Third note'),
];

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<_BulkActions> _pump(
  WidgetTester tester, {
  NotesPageExportManyFn? exportMany,
}) async {
  final db = HistoryDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);
  final actions = _BulkActions(db, _notes);
  await tester.pumpWidget(
    makeTestable(
      // The undo notice lives in the shell's notice bar, not in the page.
      Column(
        children: [
          Expanded(
            child: exportMany == null
                ? const NotesPage()
                : NotesPage(exportManyFn: exportMany),
          ),
          const WpNoticeBar(),
        ],
      ),
      size: const Size(1400, 900),
      overrides: [
        notesProvider.overrideWith((ref) => Stream.value(_notes)),
        notesActionsProvider.overrideWith((ref) => actions),
        allNoteTagsProvider.overrideWith((ref) => Stream.value(const {})),
        noteTagsProvider.overrideWith((ref, noteId) => Stream.value(const [])),
      ],
      locale: const Locale('en'),
    ),
  );
  await _settle(tester);
  return actions;
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(ValueKey(key)));
  await _settle(tester);
}

Future<void> _more(WidgetTester tester, String id) async {
  await _tap(tester, 'notes-multiselect-more');
  await _tap(tester, 'notes-multiselect-more-$id');
}

void main() {
  testWidgets('select toggle is the bordered toolbar button and reports its '
      'state, like Recordings and Snippets', (tester) async {
    await _pump(tester);
    WpIconButton toggle() => tester.widget<WpIconButton>(
      find.byKey(const ValueKey('notes-select-toggle')),
    );

    expect(toggle().ghost, isFalse, reason: 'toolbar tools are never ghost');
    expect(toggle().selected, isFalse);
    await _tap(tester, 'notes-select-toggle');
    expect(toggle().selected, isTrue);
  });

  testWidgets('the default date sort shows day sections without a separate '
      'grouping button, as Recordings does', (tester) async {
    await _pump(tester);

    expect(find.byKey(const ValueKey('notes-group-by-date')), findsNothing);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('notes-group-'),
      ),
      findsWidgets,
    );
  });

  testWidgets('select button + check box: trash asks once, sends every '
      'ticked note in one call, and one undo restores them all', (
    tester,
  ) async {
    final actions = await _pump(tester);

    await _tap(tester, 'notes-select-toggle');
    await _tap(tester, 'notes-check-n2');
    await _tap(tester, 'notes-multiselect-delete');
    expect(actions.calls, isEmpty, reason: 'nothing before the confirmation');
    await _tap(tester, 'confirm-dialog-confirm');
    expect(actions.calls, ['trash:n1,n2']);

    await _tap(tester, 'notes-bulk-undo');
    expect(actions.calls, ['trash:n1,n2', 'restore:n1,n2']);
  });

  testWidgets(
    'Ctrl/Cmd+click ticks single notes; pinning is one batch with one undo',
    (tester) async {
      final actions = await _pump(tester);
      final modifier = defaultTargetPlatform == TargetPlatform.macOS
          ? LogicalKeyboardKey.meta
          : LogicalKeyboardKey.control;

      await tester.sendKeyDownEvent(modifier);
      await _tap(tester, 'n1');
      await _tap(tester, 'n3');
      await tester.sendKeyUpEvent(modifier);
      await _settle(tester);

      await _more(tester, 'favourite');
      expect(actions.calls, ['pin:true:n1,n3']);
      await _tap(tester, 'notes-bulk-undo');
      expect(actions.calls.last, 'pin:false:n1,n3');
    },
    variant: TargetPlatformVariant.desktop(),
  );

  testWidgets('Shift+click ticks a range; tagging adds one tag to all and '
      'the undo removes exactly the added links', (tester) async {
    final actions = await _pump(tester);

    await _tap(tester, 'n1');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await _tap(tester, 'n3');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await _settle(tester);

    await _more(tester, 'tag');
    await tester.enterText(
      find.byKey(const ValueKey('notes-bulk-tag-field')),
      'work',
    );
    await _settle(tester);
    await _tap(tester, 'notes-bulk-tag-confirm');
    expect(actions.calls, ['tag:work:n1,n2,n3']);

    await _tap(tester, 'notes-bulk-undo');
    expect(actions.calls.last, 'untag:t1:n1,n2,n3');
  });

  testWidgets('Ctrl/Cmd+A selects all; merge confirms, then one undo '
      'removes the merged note and restores the sources', (tester) async {
    final actions = await _pump(tester);

    await _tap(tester, 'notes-select-toggle');
    final modifier = defaultTargetPlatform == TargetPlatform.macOS
        ? LogicalKeyboardKey.meta
        : LogicalKeyboardKey.control;
    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(modifier);
    await _settle(tester);

    await _more(tester, 'merge');
    await _tap(tester, 'confirm-dialog-confirm');
    expect(actions.calls, ['merge:n1,n2,n3']);

    await _tap(tester, 'notes-bulk-undo');
    expect(actions.calls.last, 'unmerge:m:n1,n2,n3');
  });

  testWidgets('export hands the full ticked notes to one export call', (
    tester,
  ) async {
    List<String>? exported;
    await _pump(
      tester,
      exportMany: (context, notes, tags) async {
        exported = [for (final n in notes) n.id];
      },
    );

    await _tap(tester, 'notes-select-toggle');
    await _tap(tester, 'notes-check-n3');
    await _more(tester, 'export');
    expect(exported, ['n1', 'n3']);
  });

  testWidgets('unticking the last note keeps the bar with 0 selected between '
      'search row and list', (tester) async {
    final actions = await _pump(tester);

    await _tap(tester, 'notes-select-toggle');
    await _tap(tester, 'notes-check-n1');
    expect(find.byType(WpMultiSelectBar), findsOneWidget);
    expect(find.text('0 selected'), findsOneWidget);
    final bar = tester.getRect(find.byType(WpMultiSelectBar));
    expect(
      bar.top,
      greaterThanOrEqualTo(
        tester.getRect(find.byType(WpCollectionToolbar)).bottom,
      ),
    );
    expect(
      bar.bottom,
      lessThanOrEqualTo(
        tester.getRect(find.byKey(const ValueKey('notes-list-area'))).top,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('notes-multiselect-delete')));
    await _settle(tester);
    expect(actions.calls, isEmpty, reason: 'nothing to delete');
  });
}
