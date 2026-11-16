import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';

void main() {
  group('Smart-Mode undo (swap model, v27)', () {
    late HistoryDatabase db;

    setUp(() {
      db = HistoryDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() => db.close());

    /// Seeds an entry as a Smart-Mode run leaves it: the content is the result,
    /// [raw] is the transcript (originalTranscript), and [input] is set only
    /// when it differs from the raw text (BIZ-25).
    Future<void> seed({
      String content = 'Smart-Ergebnis',
      String raw = 'Rohtext',
      String? input,
      bool applied = true,
    }) {
      return db.insertHistoryEntry(
        HistoryEntriesCompanion(
          id: const Value('e1'),
          content: Value(content),
          title: const Value('Titel'),
          timestamp: Value(DateTime(2026, 10, 18)),
          originalTranscript: Value(raw),
          smartModeInput: Value(input),
          smartModeApplied: Value(applied),
        ),
      );
    }

    test(
      'undo swaps the content to the raw input and keeps the result',
      () async {
        await seed();

        expect(await db.undoSmartMode('e1'), isTrue);

        final entry = (await db.getEntry('e1'))!;
        expect(entry.content, 'Rohtext');
        expect(entry.smartModeOutput, 'Smart-Ergebnis');
        expect(await db.undoSmartMode('e1'), isFalse);
      },
    );

    test(
      'an input that differs from the raw text is used as the undo input',
      () async {
        await seed(input: 'Rohtext mit Ersetzung');

        expect(await db.undoSmartMode('e1'), isTrue);
        expect((await db.getEntry('e1'))!.content, 'Rohtext mit Ersetzung');
      },
    );

    test('identity is stored as NULL and resolves to the raw text', () async {
      await seed();

      final entry = (await db.getEntry('e1'))!;
      expect(entry.smartModeInput, isNull);
      expect(entry.originalTranscript, 'Rohtext');
    });

    test('restore swaps back and clears the stored output', () async {
      await seed();
      await db.undoSmartMode('e1');

      expect(await db.restoreSmartModeOutput('e1'), isTrue);

      final entry = (await db.getEntry('e1'))!;
      expect(entry.content, 'Smart-Ergebnis');
      expect(entry.smartModeOutput, isNull);
      expect(entry.smartModeApplied, isTrue);
      expect(await db.restoreSmartModeOutput('e1'), isFalse);
    });

    test('an entry without a Smart-Mode run cannot be undone', () async {
      await seed(applied: false);

      expect(await db.undoSmartMode('e1'), isFalse);
      expect((await db.getEntry('e1'))!.content, 'Smart-Ergebnis');
    });

    test(
      'a manual edit ends the run and keeps the edited text (DEV-54)',
      () async {
        await seed();
        await db.updateEntry(
          'e1',
          const HistoryEntriesCompanion(content: Value('Manuell korrigiert')),
        );

        expect(await db.undoSmartMode('e1'), isFalse);
        expect(await db.restoreSmartModeOutput('e1'), isFalse);
        final entry = (await db.getEntry('e1'))!;
        expect(entry.content, 'Manuell korrigiert');
        expect(entry.smartModeInput, isNull);
        expect(entry.smartModeOutput, isNull);
        expect(entry.smartModeApplied, isNull);
      },
    );

    test('a re-transcription ends the run the same way', () async {
      await seed();
      await db.updateEntry(
        'e1',
        const HistoryEntriesCompanion(content: Value('Neu transkribiert')),
      );

      expect(await db.undoSmartMode('e1'), isFalse);
      expect((await db.getEntry('e1'))!.content, 'Neu transkribiert');
    });

    test('a metadata edit keeps the undo', () async {
      await seed();
      await db.updateEntry(
        'e1',
        const HistoryEntriesCompanion(title: Value('Umbenannt')),
      );

      expect(await db.undoSmartMode('e1'), isTrue);
    });

    test(
      'an undo followed by a manual edit cannot be restored over it',
      () async {
        await seed();
        await db.undoSmartMode('e1');
        await db.updateEntry(
          'e1',
          const HistoryEntriesCompanion(content: Value('Von Hand')),
        );

        expect(await db.restoreSmartModeOutput('e1'), isFalse);
        expect((await db.getEntry('e1'))!.content, 'Von Hand');
      },
    );
  });

  group('Smart-Mode drafts end with their entry (BIZ-24)', () {
    late HistoryDatabase db;

    setUp(() {
      db = HistoryDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() => db.close());

    Future<void> seed(String id, {String content = 'Smart-Ergebnis'}) {
      return db.insertHistoryEntry(
        HistoryEntriesCompanion(
          id: Value(id),
          content: Value(content),
          title: const Value('Titel'),
          timestamp: Value(DateTime(2026, 10, 18)),
          originalTranscript: const Value('Rohtext'),
          smartModeApplied: const Value(true),
        ),
      );
    }

    test(
      'merging entries ends the run, so the merged text cannot be undone',
      () async {
        await seed('e1');
        await seed('e2', content: 'Zweiter Eintrag');

        await db.mergeEntries(['e1', 'e2']);

        final merged = (await db.getEntry('e1'))!;
        expect(merged.content, contains('Zweiter Eintrag'));
        expect(merged.smartModeInput, isNull);
        expect(merged.smartModeOutput, isNull);
        expect(merged.smartModeApplied, isNull);
        expect(await db.undoSmartMode('e1'), isFalse);
        expect((await db.getEntry('e1'))!.content, merged.content);
      },
    );

    test('a duplicate starts without any Smart-Mode draft', () async {
      await seed('e1');

      final copy = await db.duplicateEntry('e1');

      expect(copy, isNotNull);
      expect(copy!.smartModeInput, isNull);
      expect(copy.smartModeOutput, isNull);
      expect(copy.smartModeApplied, isNull);
    });

    test('a trashed entry keeps its undo until the trash is purged', () async {
      await seed('e1');
      await db.softDeleteEntry('e1');
      await db.restoreEntry('e1');

      expect(await db.undoSmartMode('e1'), isTrue);
    });

    test(
      'a trashed entry is not undone while it sits in the trash (GS-041)',
      () async {
        await seed('e1');
        await db.softDeleteEntry('e1');

        expect(await db.undoSmartMode('e1'), isFalse);
        expect((await db.getEntry('e1'))!.smartModeOutput, isNull);
      },
    );

    test('purging the trash removes the entry with its drafts', () async {
      await seed('e1');
      await db.updateEntry(
        'e1',
        HistoryEntriesCompanion(deletedAt: Value(DateTime(2020))),
      );

      expect(await db.purgeTrash(), 1);

      expect(await db.getEntry('e1'), isNull);
    });

    test('deleting all data leaves no entry and no draft', () async {
      await seed('e1');

      await db.deleteAllData();

      expect(await db.getEntry('e1'), isNull);
    });
  });
}
