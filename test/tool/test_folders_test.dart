import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/check_test_folders.dart';

void main() {
  test('every folder with tests is assigned to a run', () {
    expect(checkTestFolders(Directory.current), isEmpty);
  });

  test('a new test folder that is wired nowhere turns the guard red', () {
    final root = Directory.systemTemp.createTempSync('test_folders_');
    addTearDown(() => root.deleteSync(recursive: true));
    Directory('${root.path}/tool').createSync();
    File(
      '${root.path}/tool/test_folders.json',
    ).writeAsStringSync('{"entries": []}');
    Directory('${root.path}/orphan_tests').createSync();
    File('${root.path}/orphan_tests/thing_test.dart').writeAsStringSync('');

    final problems = checkTestFolders(root);
    expect(problems, hasLength(1));
    expect(problems.single, contains('orphan_tests'));
  });

  test('an assignment whose run no longer names the folder is red', () {
    final root = Directory.systemTemp.createTempSync('test_folders_');
    addTearDown(() => root.deleteSync(recursive: true));
    Directory('${root.path}/tool').createSync();
    Directory('${root.path}/pkg/test').createSync(recursive: true);
    File('${root.path}/pkg/test/a_test.dart').writeAsStringSync('');
    File('${root.path}/ci.yml').writeAsStringSync('run: nothing');
    File('${root.path}/tool/test_folders.json').writeAsStringSync(
      '{"entries":[{"path":"pkg","run":"x","file":"ci.yml","needle":"pkg"}]}',
    );

    expect(checkTestFolders(root).single, contains('lacks "pkg"'));
  });
}
