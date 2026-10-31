import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/core/logging/install_id.dart';
import 'package:whispaste_diagnostics/whispaste_diagnostics.dart'
    show installIdFileName;

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('install_id_test');
    resetInstallIdCacheForTesting();
  });

  tearDown(() {
    resetInstallIdCacheForTesting();
    dir.deleteSync(recursive: true);
  });

  final hex12 = RegExp(r'^[0-9a-f]{12}$');

  test('a new install gets a random 12-hex id and keeps it on disk', () {
    final id = readInstallId(directory: dir.path);

    expect(id, matches(hex12));
    expect(
      File(p.join(dir.path, installIdFileName)).readAsStringSync().trim(),
      id,
    );
  });

  test('the stored id survives a restart', () {
    final first = readInstallId(directory: dir.path);
    resetInstallIdCacheForTesting();

    expect(readInstallId(directory: dir.path), first);
  });

  test('two installs get different ids', () {
    final other = Directory.systemTemp.createTempSync('install_id_other');
    addTearDown(() => other.deleteSync(recursive: true));

    final a = readInstallId(directory: dir.path);
    resetInstallIdCacheForTesting();
    final b = readInstallId(directory: other.path);

    expect(a, isNot(b));
  });

  test('the id is not derived from the hostname', () {
    final id = readInstallId(directory: dir.path);
    resetInstallIdCacheForTesting();
    File(p.join(dir.path, installIdFileName)).deleteSync();

    // Same machine, same hostname: a hostname hash would repeat here.
    expect(readInstallId(directory: dir.path), isNot(id));
  });

  test('a damaged file is replaced by a fresh id', () {
    File(p.join(dir.path, installIdFileName)).writeAsStringSync('my-laptop');

    final id = readInstallId(directory: dir.path);

    expect(id, matches(hex12));
    expect(id, isNot('my-laptop'));
  });

  test('an unwritable location still yields a stable id for the run', () {
    final missing = p.join(dir.path, 'missing', 'deeper');
    File(p.join(dir.path, 'missing')).writeAsStringSync('a file, not a dir');

    final id = readInstallId(directory: missing);

    expect(id, matches(hex12));
    expect(readInstallId(directory: missing), id);
  });
}
