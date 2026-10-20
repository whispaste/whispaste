import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/features/history/data/history_lock.dart';
import 'package:whispaste/services/audio/retention/pending_wipe.dart';
import 'package:whispaste/services/path_service.dart' as paths;

/// Points every audio folder and the app data folder at a fresh temp root, so
/// the wipe never touches the real user data.
Directory _setUpRoot(String prefix) {
  final root = Directory.systemTemp.createTempSync(prefix);
  addTearDown(() => root.deleteSync(recursive: true));
  paths.appDataDirOverride = root.path;
  addTearDown(() => paths.appDataDirOverride = null);
  final recordings = Directory(p.join(root.path, 'recordings'))..createSync();
  paths.retainedAudioDirOverride = recordings.path;
  addTearDown(() => paths.retainedAudioDirOverride = null);
  return root;
}

Future<ProviderContainer> _container() async {
  final db = HistoryDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);
  final container = ProviderContainer(
    overrides: [historyDatabaseProvider.overrideWithValue(db)],
  );
  addTearDown(container.dispose);
  return container;
}

Map<String, dynamic> _pendingJson() =>
    jsonDecode(File(paths.pendingWipeFile()).readAsStringSync())
        as Map<String, dynamic>;

void main() {
  test(
    '"Forgot PIN" wipe removes retained WAVs, the journal and import scratch',
    () async {
      final root = _setUpRoot('wp71-wiper-');
      final recordings = Directory(paths.retainedAudioDir());
      File(p.join(recordings.path, 'whispaste_1.wav')).writeAsStringSync('pcm');
      final journal = Directory(p.join(recordings.path, 'journal'))
        ..createSync();
      File(p.join(journal.path, 'entry.json')).writeAsStringSync('{}');
      final work = Directory(p.join(root.path, 'imports', 'work'))
        ..createSync(recursive: true);
      final scratch = File(p.join(work.path, 'source.m4a'))
        ..writeAsStringSync('audio');

      final container = await _container();
      final outcome = await container.read(historyWiperProvider)();

      expect(
        File(p.join(recordings.path, 'whispaste_1.wav')).existsSync(),
        isFalse,
      );
      expect(journal.existsSync(), isFalse);
      expect(scratch.existsSync(), isFalse);
      expect(outcome.leftovers, 0);
      expect(outcome.queued, isTrue);
    },
  );

  test('the Forgot PIN wipe removes the pre-migration history copy', () async {
    final root = _setUpRoot('wp74-wiper-backup-');
    final backup = File(p.join(root.path, 'history.db.pre-migration'))
      ..writeAsStringSync('plaintext history');

    final container = await _container();
    final outcome = await container.read(historyWiperProvider)();

    expect(backup.existsSync(), isFalse);
    expect(outcome.leftovers, 0);
    expect(outcome.migrationCopyLeft, isNull);
  });

  test(
    'a pre-migration copy that cannot be removed is reported by path, not as audio',
    () async {
      final root = _setUpRoot('wp74-wiper-backup-locked-');
      final backup = File(p.join(root.path, 'history.db.pre-migration'))
        ..writeAsStringSync('plaintext history');
      // A read-only app folder: its files cannot be unlinked.
      addTearDown(() => Process.runSync('chmod', ['755', root.path]));
      Process.runSync('chmod', ['555', root.path]);

      final container = await _container();
      final outcome = await container.read(historyWiperProvider)();

      expect(backup.existsSync(), isTrue);
      expect(outcome.migrationCopyLeft, backup.path);
      expect(outcome.leftovers, 0, reason: 'the copy is not audio');
      expect(outcome.queued, isTrue);
      expect(
        outcome.folder,
        '',
        reason: 'the copy is not queued, so no audio folder is named',
      );
    },
    skip: Platform.isWindows ? 'chmod does not lock folders on Windows' : false,
  );

  test(
    'an undeletable copy next to an audio leftover queues only the audio',
    () async {
      final root = _setUpRoot('wp74-wiper-copy-and-audio-');
      final backup = File(p.join(root.path, 'history.db.pre-migration'))
        ..writeAsStringSync('plaintext history');
      final recordings = Directory(paths.retainedAudioDir());
      final journal = Directory(p.join(recordings.path, 'journal'))
        ..createSync();
      final entry = File(p.join(journal.path, 'entry.json'))
        ..writeAsStringSync('{}');
      // The queue file is written into the app folder, which stays writable
      // for the file itself; only new entries need the folder.
      File(paths.pendingWipeFile()).writeAsStringSync('{}');
      addTearDown(() => Process.runSync('chmod', ['755', root.path]));
      addTearDown(() => Process.runSync('chmod', ['755', journal.path]));
      Process.runSync('chmod', ['555', root.path]);
      Process.runSync('chmod', ['555', journal.path]);

      final container = await _container();
      final outcome = await container.read(historyWiperProvider)();

      expect(outcome.migrationCopyLeft, backup.path);
      expect(outcome.leftovers, 1, reason: 'only the locked journal entry');
      expect(outcome.queued, isTrue);
      expect(
        outcome.folder,
        recordings.path,
        reason: 'the copy must not name its folder in the audio toast',
      );
      expect(_pendingJson().keys, [entry.path]);
    },
    skip: Platform.isWindows ? 'chmod does not lock folders on Windows' : false,
  );

  test(
    'a locked journal entry is queued as a file, not as its folder',
    () async {
      _setUpRoot('wp71-wiper-locked-');
      final recordings = Directory(paths.retainedAudioDir());
      for (var i = 0; i < 20; i++) {
        File(
          p.join(recordings.path, 'whispaste_$i.wav'),
        ).writeAsStringSync('pcm');
      }
      // A read-only journal folder: its entry cannot be deleted, so the
      // recursive delete of the folder fails and only its file is queued.
      final journal = Directory(p.join(recordings.path, 'journal'))
        ..createSync();
      final entry = File(p.join(journal.path, 'entry.json'))
        ..writeAsStringSync('{}');
      addTearDown(() => Process.runSync('chmod', ['755', journal.path]));
      Process.runSync('chmod', ['555', journal.path]);

      final container = await _container();
      final outcome = await container.read(historyWiperProvider)();

      expect(
        recordings.listSync().whereType<File>().where(
          (f) => f.path.endsWith('.wav'),
        ),
        isEmpty,
        reason: 'every WAV is removed even though one entry is locked',
      );
      expect(outcome.leftovers, 1);
      expect(outcome.queued, isTrue);
      expect(
        outcome.folder,
        recordings.path,
        reason: 'the toast names the audio folder, not its journal subfolder',
      );
      expect(
        _pendingJson().keys,
        [entry.path],
        reason: 'only the file is queued, never the folder or a root',
      );
    },
    skip: Platform.isWindows ? 'chmod does not lock folders on Windows' : false,
  );

  test(
    'leftovers in recordings and imports name both audio folders, not their parent',
    () async {
      final root = _setUpRoot('wp71-wiper-two-roots-');
      final journal = Directory(p.join(paths.retainedAudioDir(), 'journal'))
        ..createSync();
      File(p.join(journal.path, 'entry.json')).writeAsStringSync('{}');
      final work = Directory(p.join(root.path, 'imports', 'work'))
        ..createSync(recursive: true);
      File(p.join(work.path, 'source.m4a')).writeAsStringSync('audio');
      for (final dir in [journal, work]) {
        addTearDown(() => Process.runSync('chmod', ['755', dir.path]));
        Process.runSync('chmod', ['555', dir.path]);
      }

      final container = await _container();
      final outcome = await container.read(historyWiperProvider)();

      expect(outcome.leftovers, 2);
      expect(
        outcome.folder,
        '${paths.retainedAudioDir()}, ${paths.importsRootDir()}',
        reason: 'the parent also holds the database, settings and models',
      );
    },
    skip: Platform.isWindows ? 'chmod does not lock folders on Windows' : false,
  );

  test(
    'a retained folder that cannot be listed queues nothing',
    () async {
      _setUpRoot('wp71-wiper-unlisted-');
      final recordings = Directory(paths.retainedAudioDir());
      File(p.join(recordings.path, 'whispaste_1.wav')).writeAsStringSync('pcm');
      addTearDown(() => Process.runSync('chmod', ['755', recordings.path]));
      Process.runSync('chmod', ['000', recordings.path]);

      final container = await _container();
      final outcome = await container.read(historyWiperProvider)();

      expect(outcome.queued, isFalse);
      expect(outcome.leftovers, greaterThan(0));
      expect(outcome.folder, paths.retainedAudioDir());
      expect(
        File(paths.pendingWipeFile()).existsSync(),
        isFalse,
        reason: 'an unlistable folder must not produce a pending list',
      );
    },
    skip: Platform.isWindows ? 'chmod does not lock folders on Windows' : false,
  );

  test(
    'files left by the wipe are removed at the next start, new files survive',
    () async {
      _setUpRoot('wp71-wiper-next-');
      final recordings = Directory(paths.retainedAudioDir());
      final wav = File(p.join(recordings.path, 'whispaste_1.wav'))
        ..writeAsStringSync('pcm');
      final journal = Directory(p.join(recordings.path, 'journal'))
        ..createSync();
      final entry = File(p.join(journal.path, 'entry.json'))
        ..writeAsStringSync('{"wavPath": "${wav.path}"}');
      // Read-only retained and journal folders: neither the WAV nor the journal
      // entry can be removed during the wipe, like a file still held by another
      // process.
      addTearDown(
        () => Process.runSync('chmod', ['-R', '755', recordings.path]),
      );
      Process.runSync('chmod', ['555', journal.path]);
      Process.runSync('chmod', ['555', recordings.path]);

      final container = await _container();
      final outcome = await container.read(historyWiperProvider)();
      expect(outcome.queued, isTrue);
      expect(wav.existsSync(), isTrue, reason: 'still locked during the wipe');

      // The lock is released. A new recording gets a new name; a reused path
      // gets a modification time after the wipe.
      Process.runSync('chmod', ['-R', '755', recordings.path]);
      expect(_pendingJson()[entry.path], isA<Map<String, dynamic>>());
      final fresh = File(p.join(recordings.path, 'whispaste_2.wav'))
        ..writeAsStringSync('new');
      // Same path, new content: the signature no longer matches.
      entry.writeAsStringSync(
        '{"version": 1, "id": "new", "startedAt": "2026-10-18T10:00:00", '
        '"wavPath": null}',
      );

      final remaining = await applyPendingWipe(
        referencedPaths: () async => <String>{},
      );

      expect(remaining, 0);
      expect(wav.existsSync(), isFalse, reason: 'old leftover removed');
      expect(entry.existsSync(), isTrue, reason: 'replaced file is kept');
      expect(fresh.existsSync(), isTrue, reason: 'new recording survives');
      expect(File(paths.pendingWipeFile()).existsSync(), isFalse);
    },
    skip: Platform.isWindows ? 'chmod does not lock folders on Windows' : false,
  );

  test('a queued file that an attachment row still names is kept', () async {
    _setUpRoot('wp71-pending-referenced-');
    final recordings = Directory(paths.retainedAudioDir())..createSync();
    final wav = File(p.join(recordings.path, 'whispaste_9.wav'))
      ..writeAsStringSync('pcm');
    expect(await recordPendingWipe([wav.path]), isTrue);

    final remaining = await applyPendingWipe(
      referencedPaths: () async => {wav.path},
    );

    expect(remaining, 1);
    expect(wav.existsSync(), isTrue);
  });

  test('only audio files inside the audio folders are queued', () async {
    final root = _setUpRoot('wp71-pending-guard-');
    final recordings = paths.retainedAudioDir();
    final journal = Directory(p.join(recordings, 'journal'))
      ..createSync(recursive: true);
    final settings = File(p.join(root.path, 'settings.json'))
      ..writeAsStringSync('{}');

    expect(await recordPendingWipe([settings.path]), isFalse);
    expect(await recordPendingWipe([recordings]), isFalse);
    expect(await recordPendingWipe([paths.importsRootDir()]), isFalse);
    expect(
      await recordPendingWipe([journal.path]),
      isFalse,
      reason: 'the journal folder as a whole is refused',
    );
    expect(File(paths.pendingWipeFile()).existsSync(), isFalse);
  });
}
