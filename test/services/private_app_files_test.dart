@Tags(['process'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/services/private_app_files.dart';

int _mode(String path) => FileStat.statSync(path).mode & 0x1FF;

void main() {
  final skip = Platform.isWindows ? 'POSIX permissions only' : null;
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('wp-private-'));
  tearDown(() => root.deleteSync(recursive: true));

  test('folder becomes 0700, its files and logs 0600', skip: skip, () async {
    final app = Directory(p.join(root.path, 'app'))..createSync();
    Process.runSync('chmod', ['775', app.path]);
    final logs = Directory(p.join(app.path, 'logs'))..createSync();
    final files = [
      for (final name in [
        'history.db',
        'history.db-wal',
        'history.db-shm',
        'install_id',
        'shared_preferences.json',
      ])
        File(p.join(app.path, name))..writeAsStringSync('x'),
      File(p.join(logs.path, 'whispaste.log'))..writeAsStringSync('x'),
    ];
    for (final f in files) {
      Process.runSync('chmod', ['664', f.path]);
    }

    await hardenPrivateAppFiles([app.path], posix: true);

    expect(_mode(app.path), 0x1C0);
    expect(_mode(logs.path), 0x1C0);
    for (final f in files) {
      expect(_mode(f.path), 0x180, reason: f.path);
    }
  });

  test(
    'a symlinked folder and a missing folder are left alone',
    skip: skip,
    () async {
      final target = Directory(p.join(root.path, 'target'))..createSync();
      Process.runSync('chmod', ['755', target.path]);
      final link = Link(p.join(root.path, 'link'))..createSync(target.path);

      await hardenPrivateAppFiles([
        link.path,
        p.join(root.path, 'missing'),
        '',
      ], posix: true);

      expect(_mode(target.path), 0x1ED);
    },
  );

  test('does nothing on a non-POSIX host', () async {
    final app = Directory(p.join(root.path, 'app'))..createSync();
    final before = _mode(app.path);
    await hardenPrivateAppFiles([app.path], posix: false);
    expect(_mode(app.path), before);
    expect(app.existsSync(), isTrue);
  });
}
