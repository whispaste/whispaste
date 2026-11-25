import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/data/editor_view_state.dart';

/// #678: the remembered place of an entry lives beside its text, survives a
/// restart and goes with the entry.
void main() {
  const state = EditorViewState(
    selectionBase: 3,
    selectionExtent: 9,
    anchorBlock: 2,
    anchorOffset: 14.5,
    zoom: 1.3,
    folded: [1],
  );

  Future<void> recording(HistoryDatabase db, String id, String text) =>
      db.upsertEntry(
        HistoryEntriesCompanion.insert(
          id: id,
          timestamp: DateTime(2026),
          content: Value(text),
        ),
      );

  test(
    'state survives closing and reopening the database, text untouched',
    () async {
      final dir = await Directory.systemTemp.createTemp('wp_view_state');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/history.db');
      const text = 'first line\nsecond line\nthird line';

      final first = HistoryDatabase.forTesting(NativeDatabase(file));
      await recording(first, 'r', text);
      await first.viewStates.initialize();
      await first.viewStates.save((
        kind: ContentKind.recording,
        id: 'r',
      ), state);
      await first.close();

      final second = HistoryDatabase.forTesting(NativeDatabase(file));
      addTearDown(second.close);
      await second.viewStates.initialize();
      expect(
        await second.viewStates.read((kind: ContentKind.recording, id: 'r')),
        state,
      );
      final entry = await second.getEntry('r');
      expect(entry?.content, text);
    },
  );

  group('store', () {
    late HistoryDatabase db;
    setUp(() async {
      db = HistoryDatabase.forTesting(NativeDatabase.memory());
      await db.viewStates.initialize();
    });
    tearDown(() => db.close());

    test('deleting an entry removes its state for every kind', () async {
      await recording(db, 'r', 'text');
      final note = await db.createNote();
      await db.upsertSnippet(
        id: 's',
        title: 'S',
        body: 'body',
        createdAt: DateTime(2026),
      );
      final keys = <ContentKey>[
        (kind: ContentKind.recording, id: 'r'),
        (kind: ContentKind.recordingEdited, id: 'r'),
        (kind: ContentKind.note, id: note.id),
        (kind: ContentKind.snippet, id: 's'),
      ];
      for (final key in keys) {
        await db.viewStates.save(key, state);
        expect(await db.viewStates.read(key), state, reason: '$key');
      }

      await db.permanentDeleteEntry('r');
      await db.permanentDeleteNote(note.id);
      await db.deleteSnippet('s');

      for (final key in keys) {
        expect(await db.viewStates.read(key), isNull, reason: '$key');
      }
      final rows = await db
          .customSelect('SELECT COUNT(*) AS c FROM editor_view_states')
          .getSingle();
      expect(rows.read<int>('c'), 0);
    });

    test('a save for an entry that no longer exists stores nothing', () async {
      const key = (kind: ContentKind.note, id: 'gone');
      await db.viewStates.save(key, state);
      expect(await db.viewStates.read(key), isNull);
    });

    test('a later save replaces the earlier one', () async {
      await recording(db, 'r', 'text');
      const key = (kind: ContentKind.recording, id: 'r');
      await db.viewStates.save(key, state);
      await db.viewStates.save(key, state.copyWith(zoom: 2));
      expect((await db.viewStates.read(key))?.zoom, 2);
    });

    test('the sweep on open drops states left behind', () async {
      await db.customStatement(
        'INSERT INTO editor_view_states(kind, id, state) VALUES '
        "('note', 'orphan', '{}'), ('unknownKind', 'x', '{}')",
      );
      await db.viewStates.initialize();
      final rows = await db
          .customSelect('SELECT COUNT(*) AS c FROM editor_view_states')
          .getSingle();
      expect(rows.read<int>('c'), 0);
    });
  });

  group('EditorViewState', () {
    test('json round trip; foreign or broken rows are ignored', () {
      expect(EditorViewState.fromJson(state.toJson()), state);
      expect(EditorViewState.fromJson({...state.toJson(), 'v': 99}), isNull);
      expect(EditorViewState.fromJson('nonsense'), isNull);
      expect(
        EditorViewState.fromJson({'v': EditorViewState.version, 'zoom': 40}),
        const EditorViewState(zoom: EditorViewState.maxZoom),
      );
    });

    test('clampedTo fits a state to a text that changed meanwhile', () {
      final clamped = state
          .copyWith(
            selectionBase: 100,
            selectionExtent: -4,
            anchorBlock: 7,
            anchorOffset: -3,
            folded: [0, 1, 5],
          )
          .clampedTo('ab\ncd');
      expect(
        clamped,
        const EditorViewState(
          selectionBase: 5,
          selectionExtent: 0,
          anchorBlock: 1,
          anchorOffset: 0,
          zoom: 1.3,
          folded: [0, 1],
        ),
      );
    });

    test('a stored zoom is clamped and kept, not lost', () {
      expect(EditorViewState.clampZoom(double.nan), 1.0);
      expect(EditorViewState.clampZoom(9), EditorViewState.maxZoom);
    });

    test('paragraph helpers agree with each other', () {
      const text = 'one\ntwo\n\nfour';
      expect(EditorViewState.paragraphCount(text), 4);
      expect(EditorViewState.paragraphCount(''), 1);
      expect(EditorViewState.paragraphAt(text, 0), 0);
      expect(EditorViewState.paragraphAt(text, 5), 1);
      expect(EditorViewState.paragraphAt(text, text.length), 3);
      for (var i = 0; i < 4; i++) {
        final start = EditorViewState.paragraphStart(text, i);
        expect(EditorViewState.paragraphAt(text, start), i);
      }
      expect(EditorViewState.paragraphStart(text, 9), text.length);
    });
  });
}
