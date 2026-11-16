import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/services/app_identity/app_identity_service.dart';

/// Deleting recordings for good also drops the cached name and icon of every
/// app no remaining recording names; trashed recordings keep theirs, since
/// they can still be restored.
void main() {
  late Directory root;
  late String dir;
  late HistoryDatabase db;
  late AppIdentityService identities;

  final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]);

  setUp(() async {
    root = Directory.systemTemp.createTempSync('app_identity_prune_test');
    dir = p.join(root.path, appIconFolderName);
    db = HistoryDatabase.forTesting(NativeDatabase.memory());
    identities = AppIdentityService(
      directory: dir,
      lookup: (id, size, _) async => NativeAppInfo(name: id, iconPng: png),
    );
    for (final (id, app) in [('e1', 'slack'), ('e2', 'mail'), ('e3', 'code')]) {
      await db.insertHistoryEntry(
        HistoryEntriesCompanion(
          id: Value(id),
          content: const Value('Text'),
          timestamp: Value(DateTime(2026, 10, 31)),
          targetApp: Value(app),
        ),
      );
      await identities.resolve(app);
    }
  });

  tearDown(() async {
    await db.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  String index() => File(p.join(dir, 'index.json')).readAsStringSync();
  int icons() =>
      Directory(dir).listSync().where((f) => f.path.endsWith('.png')).length;

  test('a recording deleted for good takes its app out of the cache', () async {
    await db.permanentDeleteEntry('e1');
    await pruneAppIdentityCache(db, identities);

    expect(index(), isNot(contains('slack')));
    expect(index(), allOf(contains('mail'), contains('code')));
    expect(icons(), 2);
  });

  test(
    'a trashed recording keeps its app until the trash is emptied',
    () async {
      await db.softDeleteEntry('e2');
      await pruneAppIdentityCache(db, identities);
      expect(index(), contains('mail'));

      await db.emptyTrash();
      await pruneAppIdentityCache(db, identities);
      expect(index(), isNot(contains('mail')));
      expect(icons(), 2);
    },
  );

  test('an app still named by another recording stays', () async {
    await db.insertHistoryEntry(
      HistoryEntriesCompanion(
        id: const Value('e4'),
        content: const Value('Text'),
        timestamp: Value(DateTime(2026, 10, 31)),
        targetApp: const Value('slack'),
      ),
    );
    await db.permanentDeleteEntry('e1');
    await pruneAppIdentityCache(db, identities);

    expect(index(), contains('slack'));
    expect(icons(), 3);
  });
}
