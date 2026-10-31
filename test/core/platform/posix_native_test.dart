import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/platform/posix_native.dart';

void main() {
  final posix = Platform.isMacOS || Platform.isLinux;

  group('posix_native', () {
    late Directory root;
    setUp(() => root = Directory.systemTemp.createTempSync('wp_posix_native_'));
    tearDown(() => root.deleteSync(recursive: true));

    test('nativeChmod sets the mode without spawning chmod', () {
      final file = File('${root.path}/f.txt')..writeAsStringSync('x');
      expect(nativeChmod(file.path, 0x180), isTrue);
      expect(FileStat.statSync(file.path).mode & 0x1FF, 0x180);
    }, skip: posix ? null : 'POSIX permissions only');

    test('nativeChmod reports a missing path as failure', () {
      expect(nativeChmod('${root.path}/missing', 0x180), isFalse);
    }, skip: posix ? null : 'POSIX permissions only');

    test(
      'nativeOwnerUid matches the current user for files the test creates',
      () {
        final file = File('${root.path}/owned.txt')..writeAsStringSync('x');
        expect(nativeOwnerUid(file.path), nativeGetUid());
      },
      skip: Platform.isMacOS ? null : 'stat layout is macOS-only',
    );
  });
}
