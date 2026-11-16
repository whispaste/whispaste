/// The "Forgot PIN?" wipe takes the notes with it (coordinator decision on
/// GS-149): their rows, version history, tags and image files are removed.
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/data/note_asset_storage.dart';
import 'package:whispaste/features/history/data/history_lock.dart';
import 'package:whispaste/services/path_service.dart' as paths;

void main() {
  test(
    '"Forgot PIN" wipe deletes notes, versions, tags and image files',
    () async {
      final root = Directory.systemTemp.createTempSync('wp31a-wipe-notes-');
      addTearDown(() => root.deleteSync(recursive: true));
      paths.appDataDirOverride = root.path;
      addTearDown(() => paths.appDataDirOverride = null);
      final recordings = Directory(p.join(root.path, 'recordings'))
        ..createSync();
      paths.retainedAudioDirOverride = recordings.path;
      addTearDown(() => paths.retainedAudioDirOverride = null);

      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final note = await db.createNote();
      await db.updateNoteContent(note.id, 'Geheimer Text');
      await db.recordNoteVersionIfChanged(
        note.id,
        title: 'Titel',
        content: 'Geheimer Text',
        now: DateTime(2026, 10, 1),
      );
      await db.insertNoteAsset(
        NoteAssetsCompanion.insert(
          id: 'a1',
          noteId: note.id,
          relativePath: '$noteAssetFolderName/${note.id}/a1.png',
          mimeType: 'image/png',
          sizeBytes: 3,
          width: 1,
          height: 1,
          createdAt: DateTime(2026, 10, 1),
        ),
      );
      final imageDir = Directory(
        p.join(root.path, noteAssetFolderName, note.id),
      )..createSync(recursive: true);
      final image = File(p.join(imageDir.path, 'a1.png'))
        ..writeAsBytesSync([1, 2, 3]);

      final container = ProviderContainer(
        overrides: [historyDatabaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);
      await container.read(historyWiperProvider)();

      expect(await db.select(db.notes).get(), isEmpty);
      expect(await db.select(db.noteVersions).get(), isEmpty);
      expect(await db.select(db.noteAssets).get(), isEmpty);
      expect(image.existsSync(), isFalse);
      expect(
        Directory(p.join(root.path, noteAssetFolderName)).existsSync() &&
            Directory(
              p.join(root.path, noteAssetFolderName),
            ).listSync(recursive: true).whereType<File>().isNotEmpty,
        isFalse,
      );
    },
  );
}
