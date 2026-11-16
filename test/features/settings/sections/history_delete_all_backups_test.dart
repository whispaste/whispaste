import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/data/history_backups.dart';
import 'package:whispaste/features/settings/sections/history_section.dart';
import 'package:whispaste/services/app_identity/app_identity_service.dart';
import 'package:whispaste/services/path_service.dart' as paths;

void main() {
  test('"delete all recordings" removes the upgrade backups (#562)', () async {
    final root = Directory.systemTemp.createTempSync('wp562-delete-all-');
    addTearDown(() => root.deleteSync(recursive: true));
    paths.appDataDirOverride = root.path;
    addTearDown(() => paths.appDataDirOverride = null);
    final backups = Directory(historyBackupDir(root.path))..createSync();
    File(
      p.join(backups.path, 'history-20261101-080000.db'),
    ).writeAsStringSync('plaintext history');

    final db = HistoryDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: [
        historyDatabaseProvider.overrideWithValue(db),
        appIdentityServiceProvider.overrideWithValue(
          AppIdentityService(
            directory: p.join(root.path, 'icons'),
            lookup: (_, _, _) async => null,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(historyDeleteAllEntriesProvider)();

    expect(backups.existsSync(), isFalse);
  });
}
