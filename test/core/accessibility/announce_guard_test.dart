// Guard for lib/core/accessibility/announce.dart: every screen-reader
// announcement of the app goes through announce(), so on macOS none of them
// leaves an unanswered reply on flutter/accessibility.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _wrapper = 'lib/core/accessibility/announce.dart';

// Directory.listSync yields `\` separators on Windows.
String _posix(String path) => path.replaceAll(r'\', '/');

void main() {
  test('only announce() calls SemanticsService directly', () {
    final direct = RegExp(r'SemanticsService\.(sendAnnouncement|announce)\(');
    final offenders = [
      for (final f in Directory('lib').listSync(recursive: true))
        if (f is File &&
            f.path.endsWith('.dart') &&
            _posix(f.path) != _wrapper &&
            direct.hasMatch(f.readAsStringSync()))
          _posix(f.path),
    ];
    expect(offenders, isEmpty, reason: 'use announce() from $_wrapper');
  });
}
