import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/data/history_vacuum.dart';

class _MemoryFlag implements HistoryVacuumFlag {
  bool done = false;
  int marks = 0;
  int failures = 0;

  @override
  Future<bool> isDone() async => done;

  @override
  Future<int> failedAttempts() async => failures;

  @override
  Future<void> recordFailure() async => failures++;

  @override
  Future<void> markDone() async {
    done = true;
    marks++;
  }
}

void main() {
  group('one-time VACUUM after the v27 upgrade (DEV-71)', () {
    late Directory tmpDir;
    late String dbPath;
    late HistoryDatabase db;

    setUp(() async {
      tmpDir = await Directory.systemTemp.createTemp('whispaste_vacuum_');
      dbPath = p.join(tmpDir.path, 'history.db');
      db = HistoryDatabase.forTesting(NativeDatabase(File(dbPath)));
    });

    tearDown(() async {
      await db.close();
      if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
    });

    /// Writes and deletes rows so the file carries free pages.
    Future<void> makeFreePages() async {
      final big = 'x' * 4000;
      for (var i = 0; i < 300; i++) {
        await db.insertHistoryEntry(
          HistoryEntriesCompanion(
            id: Value('e$i'),
            content: Value(big),
            title: const Value('t'),
            timestamp: Value(DateTime(2026, 1, 1)),
          ),
        );
      }
      for (var i = 0; i < 300; i++) {
        await db.permanentDeleteEntry('e$i');
      }
    }

    Future<int> freelist() async {
      final row = await db.customSelect('PRAGMA freelist_count').getSingle();
      return row.data.values.single as int;
    }

    HistoryVacuum vacuum(
      _MemoryFlag flag, {
      int? bytes = 1024,
      String? path,
      Future<void> Function()? action,
    }) => HistoryVacuum(
      database: db,
      databasePath: path ?? dbPath,
      flag: flag,
      fileSize: (_) async => bytes,
      vacuumAction: action,
    );

    test('runs once for a small file with free pages', () async {
      await makeFreePages();
      expect(await freelist(), greaterThan(0));
      final flag = _MemoryFlag();

      expect(await vacuum(flag).runOnce(), HistoryVacuumOutcome.vacuumed);
      expect(await freelist(), 0);
      expect(flag.done, isTrue);

      expect(await vacuum(flag).runOnce(), HistoryVacuumOutcome.alreadyDone);
      expect(flag.marks, 1);
    });

    test('a file above the 512 MB limit is skipped, flag stays open', () async {
      await makeFreePages();
      final flag = _MemoryFlag();

      expect(
        await vacuum(flag, bytes: historyVacuumMaxBytes + 1).runOnce(),
        HistoryVacuumOutcome.tooLarge,
      );
      expect(flag.done, isFalse);
      expect(await freelist(), greaterThan(0));
    });

    test('a file exactly at the limit still runs', () async {
      await makeFreePages();
      expect(
        await vacuum(_MemoryFlag(), bytes: historyVacuumMaxBytes).runOnce(),
        HistoryVacuumOutcome.vacuumed,
      );
    });

    test('an unknown file size is treated as too large', () async {
      await makeFreePages();
      expect(
        await vacuum(_MemoryFlag(), bytes: null).runOnce(),
        HistoryVacuumOutcome.tooLarge,
      );
    });

    test('a Windows path is judged by size only (DEV-88)', () async {
      await makeFreePages();
      const winPath = r'C:\Users\x\AppData\Roaming\whispaste\history.db';
      String? seen;
      final flag = _MemoryFlag();

      final outcome = await HistoryVacuum(
        database: db,
        databasePath: winPath,
        flag: flag,
        fileSize: (path) async {
          seen = path;
          return 4096;
        },
        vacuumAction: () async => db.customStatement('VACUUM'),
      ).runOnce();

      expect(seen, winPath);
      expect(outcome, HistoryVacuumOutcome.vacuumed);
    });

    test('without free pages nothing runs and the flag is set', () async {
      final flag = _MemoryFlag();

      expect(
        await vacuum(flag).runOnce(),
        HistoryVacuumOutcome.nothingToReclaim,
      );
      expect(flag.done, isTrue);
    });

    test('a failed VACUUM is counted and given up after three tries', () async {
      await makeFreePages();
      final flag = _MemoryFlag();
      final failing = vacuum(
        flag,
        action: () async => throw Exception('SQLITE_FULL'),
      );

      expect(await failing.runOnce(), HistoryVacuumOutcome.failed);
      expect(await failing.runOnce(), HistoryVacuumOutcome.failed);
      expect(flag.failures, 2);
      expect(flag.done, isFalse);

      expect(await failing.runOnce(), HistoryVacuumOutcome.gaveUp);
      expect(flag.failures, 3);
      expect(flag.done, isTrue);
    });

    test(
      'the scheduler timer is cancelled when the container is disposed (DEV-87)',
      () {
        final container = ProviderContainer();
        final timer = container.read(historyVacuumSchedulerProvider);
        expect(timer.isActive, isTrue);

        container.dispose();
        expect(timer.isActive, isFalse);
      },
    );

    test(
      'a VACUUM through the write coordinator succeeds next to writes',
      () async {
        await makeFreePages();
        await Future.wait([
          db.vacuum(),
          db.insertHistoryEntry(
            HistoryEntriesCompanion(
              id: const Value('late'),
              content: const Value('x'),
              title: const Value('t'),
              timestamp: Value(DateTime(2026, 1, 2)),
            ),
          ),
        ]);
        expect(await db.getEntry('late'), isNotNull);
      },
    );
  });

  group('concurrent undo and restore (DEV-69, DEV-89)', () {
    late HistoryDatabase db;

    setUp(() async {
      db = HistoryDatabase.forTesting(NativeDatabase.memory());
      await db.insertHistoryEntry(
        HistoryEntriesCompanion(
          id: const Value('e1'),
          content: const Value('Smart-Ergebnis'),
          title: const Value('T'),
          timestamp: Value(DateTime(2026, 10, 18)),
          originalTranscript: const Value('Rohtext'),
          smartModeApplied: const Value(true),
        ),
      );
    });

    tearDown(() async {
      HistoryDatabase.beforeConditionalWrite = null;
      await db.close();
    });

    test('two simultaneous undos swap the text exactly once', () async {
      final results = await Future.wait([
        db.undoSmartMode('e1'),
        db.undoSmartMode('e1'),
      ]);

      expect(results.where((r) => r).length, 1);
      final entry = (await db.getEntry('e1'))!;
      expect(entry.content, 'Rohtext');
      expect(entry.smartModeOutput, 'Smart-Ergebnis');
    });

    test('two simultaneous restores swap back exactly once', () async {
      await db.undoSmartMode('e1');

      final results = await Future.wait([
        db.restoreSmartModeOutput('e1'),
        db.restoreSmartModeOutput('e1'),
      ]);

      expect(results.where((r) => r).length, 1);
      final entry = (await db.getEntry('e1'))!;
      expect(entry.content, 'Smart-Ergebnis');
      expect(entry.smartModeOutput, isNull);
    });

    test('a manual edit between read and update wins (DEV-89)', () async {
      HistoryDatabase.beforeConditionalWrite = () async {
        await db.customUpdate(
          "UPDATE history_entries SET content = 'Von Hand' WHERE id = 'e1'",
          updates: {db.historyEntries},
        );
      };

      expect(await db.undoSmartMode('e1'), isFalse);

      final entry = (await db.getEntry('e1'))!;
      expect(entry.content, 'Von Hand');
      expect(entry.smartModeOutput, isNull);
    });

    test('an edit racing a restore wins as well (DEV-89)', () async {
      await db.undoSmartMode('e1');
      HistoryDatabase.beforeConditionalWrite = () async {
        await db.customUpdate(
          "UPDATE history_entries SET content = 'Von Hand' WHERE id = 'e1'",
          updates: {db.historyEntries},
        );
      };

      expect(await db.restoreSmartModeOutput('e1'), isFalse);
      expect((await db.getEntry('e1'))!.content, 'Von Hand');
    });
  });
}
