import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/services/audio/recovery/recording_recovery.dart';
import 'package:whispaste/services/audio/retention/pending_wipe.dart';
import 'package:whispaste/services/path_service.dart' as paths;

void main() {
  test(
    'recovery never offers a journal queued for removal, but offers a newer one',
    () async {
      final root = Directory.systemTemp.createTempSync('wp71-recovery-order-');
      addTearDown(() => root.deleteSync(recursive: true));
      paths.appDataDirOverride = root.path;
      addTearDown(() => paths.appDataDirOverride = null);
      paths.retainedAudioDirOverride = p.join(root.path, 'recordings');
      addTearDown(() => paths.retainedAudioDirOverride = null);

      final journal = Directory(p.join(root.path, 'recordings', 'journal'))
        ..createSync(recursive: true);

      // A journal left before the wipe: its file is older than the wipe and
      // was queued because the reset could not delete it.
      final old = File(p.join(journal.path, 'old.json'))
        ..writeAsStringSync(
          jsonEncode({
            'version': 1,
            'id': 'old',
            'startedAt': DateTime(2026, 1, 1).toIso8601String(),
            'wavPath': null,
          }),
        );
      expect(await recordPendingWipe([old.path]), isTrue);

      // A journal created after the wipe: not queued, so it must survive.
      File(p.join(journal.path, 'new.json')).writeAsStringSync(
        jsonEncode({
          'version': 1,
          'id': 'new',
          'startedAt': DateTime(2026, 10, 18).toIso8601String(),
          'wavPath': null,
        }),
      );

      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: [historyDatabaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);

      final scan = await container.read(interruptedRecordingsProvider.future);

      expect(scan.recordings.map((r) => r.id), [
        'new',
      ], reason: 'the queued journal is gone before the scan runs');
      expect(old.existsSync(), isFalse);
    },
  );
}
