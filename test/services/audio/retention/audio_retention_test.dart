/// Audio retention: the age rule for retained WAVs, and the sweep that deletes
/// expired files and their attachment rows. Text retention is separate.
library;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/services/audio/retention/audio_retention.dart';

void main() {
  final now = DateTime(2026, 10, 17, 12);

  RetainedAudioRef item(String id, int ageDays) => RetainedAudioRef(
    id: id,
    filePath: '/retained/$id.wav',
    createdAt: now.subtract(Duration(days: ageDays)),
  );

  group('planRetainedAudioDeletions', () {
    test('selects audio older than the limit and keeps newer audio', () {
      final plan = planRetainedAudioDeletions(
        items: [item('old', 31), item('fresh', 2)],
        now: now,
      );

      expect(plan.map((r) => r.id), ['old']);
    });

    test('keeps audio created exactly at the cutoff', () {
      final plan = planRetainedAudioDeletions(
        items: [item('edge', kRetainedAudioMaxAge.inDays)],
        now: now,
      );

      expect(plan, isEmpty);
    });

    test('honours a custom age limit', () {
      final plan = planRetainedAudioDeletions(
        items: [item('a', 3)],
        now: now,
        maxAge: const Duration(days: 2),
      );

      expect(plan.map((r) => r.id), ['a']);
    });

    test('empty input yields an empty plan', () {
      expect(planRetainedAudioDeletions(items: const [], now: now), isEmpty);
    });
  });

  group('sweepRetainedAudio', () {
    late Directory tmp;
    late HistoryDatabase db;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('wp35-retention-');
      db = HistoryDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
      await tmp.delete(recursive: true);
    });

    /// Inserts an audio attachment whose file exists on disk.
    Future<String> addAttachment(String name, DateTime createdAt) async {
      final path = '${tmp.path}/$name.wav';
      File(path).writeAsBytesSync([0, 1, 2]);
      await db
          .into(db.entryAttachments)
          .insert(
            EntryAttachmentsCompanion.insert(
              id: name,
              entryId: 'entry-$name',
              filename: '$name.wav',
              filepath: path,
              mimeType: const Value('audio/wav'),
              sizeBytes: const Value(3),
              createdAt: createdAt,
            ),
          );
      return path;
    }

    test('deletes expired files and rows and keeps fresh ones', () async {
      final oldPath = await addAttachment(
        'old',
        now.subtract(const Duration(days: 45)),
      );
      final freshPath = await addAttachment(
        'fresh',
        now.subtract(const Duration(days: 1)),
      );

      final removed = await sweepRetainedAudio(db: db, now: now);

      expect(removed, 1);
      expect(File(oldPath).existsSync(), isFalse);
      expect(File(freshPath).existsSync(), isTrue);
      final rows = await db.listAudioAttachments();
      expect(rows.map((r) => r.id), ['fresh']);
    });

    test('keeps the row of a file that cannot be deleted', () async {
      final lockedPath = await addAttachment(
        'locked',
        now.subtract(const Duration(days: 45)),
      );

      final removed = await sweepRetainedAudio(
        db: db,
        now: now,
        deleteFile: (path) async {
          if (path == lockedPath) {
            throw const FileSystemException('busy');
          }
        },
      );

      expect(removed, 0);
      final rows = await db.listAudioAttachments();
      expect(rows.map((r) => r.id), ['locked']);
    });
  });

  group('orphaned retained WAVs', () {
    final now = DateTime(2026, 10, 17, 12);

    test('plans only old WAVs that nothing refers to', () {
      final oldOrphan = RetainedWavFile(
        path: '/retained/a.wav',
        modified: now.subtract(const Duration(hours: 30)),
      );
      final oldReferenced = RetainedWavFile(
        path: '/retained/b.wav',
        modified: now.subtract(const Duration(hours: 30)),
      );
      final freshOrphan = RetainedWavFile(
        path: '/retained/c.wav',
        modified: now.subtract(const Duration(hours: 2)),
      );

      final plan = planOrphanedWavDeletions(
        files: [oldOrphan, oldReferenced, freshOrphan],
        referencedPaths: {'/retained/b.wav'},
        now: now,
      );

      expect(plan.map((f) => f.path), ['/retained/a.wav']);
    });

    // Windows only: a stored reference uses `/` while the directory listing
    // uses `\` for the same file. Before the normalisation the file counted
    // as orphaned and was deleted. Runs on the Windows CI subset.
    test(
      'a reference with other separators still protects the file on Windows',
      () {
        final listed = RetainedWavFile(
          path: r'C:\retained\b.wav',
          modified: now.subtract(const Duration(hours: 30)),
        );

        final plan = planOrphanedWavDeletions(
          files: [listed],
          referencedPaths: {'C:/retained/b.wav'},
          now: now,
        );

        expect(plan, isEmpty);
      },
      skip: Platform.isWindows ? false : 'Windows path separators only',
    );

    test(
      'sweep deletes an old orphan and keeps referenced and fresh WAVs',
      () async {
        final dir = await Directory.systemTemp.createTemp('wp35-orphans-');
        addTearDown(() => dir.delete(recursive: true));
        File oldWav(String name, {required bool old}) {
          final f = File('${dir.path}/$name')..writeAsBytesSync([0]);
          f.setLastModifiedSync(now.subtract(Duration(hours: old ? 30 : 2)));
          return f;
        }

        final orphan = oldWav('orphan.wav', old: true);
        final referenced = oldWav('referenced.wav', old: true);
        final fresh = oldWav('fresh.wav', old: false);

        final removed = await sweepOrphanedRetainedWavs(
          directory: dir.path,
          referencedPaths: {referenced.path},
          now: now,
        );

        expect(removed, 1);
        expect(orphan.existsSync(), isFalse);
        expect(referenced.existsSync(), isTrue);
        expect(fresh.existsSync(), isTrue);
      },
    );

    test('a missing folder is not an error', () async {
      final removed = await sweepOrphanedRetainedWavs(
        directory: '/definitely/not/here',
        referencedPaths: const {},
        now: now,
      );

      expect(removed, 0);
    });
  });
  group('orphaned import work', () {
    final now = DateTime(2026, 10, 18, 12);

    test('an old job folder that no live job owns is removed', () async {
      final work = await Directory.systemTemp.createTemp('wp74-import-work-');
      addTearDown(() => work.delete(recursive: true));
      final job = Directory('${work.path}/finished-job')..createSync();
      final source = File('${job.path}/source.m4a')..writeAsBytesSync([0]);
      source.setLastModifiedSync(now.subtract(const Duration(days: 31)));

      final removed = await sweepOrphanedImportWork(
        workDir: work.path,
        liveJobIds: const {},
        now: now,
      );

      expect(removed, 1);
      expect(job.existsSync(), isFalse);
    });

    test('a folder of a queued or running job is kept however old', () async {
      final work = await Directory.systemTemp.createTemp('wp74-import-live-');
      addTearDown(() => work.delete(recursive: true));
      final running = Directory('${work.path}/running-job')..createSync();
      final runningSource = File('${running.path}/source.m4a')
        ..writeAsBytesSync([0]);
      runningSource.setLastModifiedSync(
        now.subtract(const Duration(days: 400)),
      );

      final removed = await sweepOrphanedImportWork(
        workDir: work.path,
        liveJobIds: const {'running-job'},
        now: now,
      );

      expect(removed, 0);
      expect(running.existsSync(), isTrue);
    });

    test('a fresh orphan is kept until the retention period passes', () async {
      final work = await Directory.systemTemp.createTemp('wp74-import-fresh-');
      addTearDown(() => work.delete(recursive: true));
      final fresh = Directory('${work.path}/fresh-job')..createSync();
      final freshSource = File('${fresh.path}/source.m4a')
        ..writeAsBytesSync([0]);
      freshSource.setLastModifiedSync(now.subtract(const Duration(days: 2)));

      final removed = await sweepOrphanedImportWork(
        workDir: work.path,
        liveJobIds: const {},
        now: now,
      );

      expect(removed, 0);
      expect(fresh.existsSync(), isTrue);
    });
  });
}
