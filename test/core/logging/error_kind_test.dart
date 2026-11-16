import 'dart:io';

import 'package:drift/native.dart' show SqliteException;
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/logging/app_logger.dart';
import 'package:whispaste/services/transcription/transcriber_exception.dart';

const _marker = 'MARKER dictated sentence';

void main() {
  test('errorKind keeps the type and code, never the message', () {
    final cases = <Object, String>{
      SqliteException(
        extendedResultCode: 1555,
        message: _marker,
        causingStatement: 'INSERT INTO t VALUES (?)',
        parametersToStatement: const [_marker],
      ): 'SqliteException(code 1555)',
      const FileSystemException(_marker, '/tmp/x', OSError(_marker, 13)):
          'FileSystemException(errno 13)',
      PlatformException(code: 'clipboard_busy', message: _marker):
          'PlatformException(clipboard_busy)',
      const TranscriberException(
        _marker,
        reason: TranscriberFailureReason.timeout,
      ): 'TranscriberException(reason: timeout)',
      StateError(_marker): 'StateError',
      Exception(_marker): '_Exception',
    };
    for (final entry in cases.entries) {
      final kind = errorKind(entry.key);
      expect(kind, entry.value);
      expect(kind, isNot(contains('MARKER')));
    }
  });
}
