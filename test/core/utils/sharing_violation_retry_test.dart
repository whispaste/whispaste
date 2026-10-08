/// Windows refuses to delete a file another handle still holds open
/// (ERROR_SHARING_VIOLATION, errno 32 — Sentry 123406956 / 133414579).
/// Such locks are usually short-lived (an engine still reading a model, a
/// virus scan of a fresh download), so deletes retry with backoff before
/// giving up.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/utils/sharing_violation_retry.dart';

FileSystemException _locked() => const FileSystemException(
  'Cannot delete file',
  r'C:\models\ggml-small-q5_1.bin',
  // Localized OS text (Spanish Windows) — only the code may matter.
  OSError('El proceso no tiene acceso al archivo', 32),
);

void main() {
  test('isSharingViolation matches on the OS error code only', () {
    expect(isSharingViolation(_locked()), isTrue);
    expect(
      isSharingViolation(
        const FileSystemException('x', 'p', OSError('Access denied', 5)),
      ),
      isFalse,
    );
    expect(isSharingViolation(const FileSystemException('x')), isFalse);
    expect(isSharingViolation(StateError('x')), isFalse);
  });

  test(
    'retries a sharing violation and succeeds once the lock clears',
    () async {
      var calls = 0;
      final waits = <Duration>[];
      await retryOnSharingViolation(() async {
        if (++calls < 3) throw _locked();
      }, wait: (d) async => waits.add(d));
      expect(calls, 3);
      expect(waits, kSharingViolationBackoff.take(2).toList());
    },
  );

  test('gives up after the backoff budget and rethrows', () async {
    var calls = 0;
    await expectLater(
      retryOnSharingViolation(() async {
        calls++;
        throw _locked();
      }, wait: (_) async {}),
      throwsA(isA<FileSystemException>()),
    );
    expect(calls, kSharingViolationBackoff.length + 1);
  });

  test('other failures are not retried', () async {
    var calls = 0;
    await expectLater(
      retryOnSharingViolation(() async {
        calls++;
        throw const FileSystemException('x', 'p', OSError('denied', 5));
      }, wait: (_) async {}),
      throwsA(isA<FileSystemException>()),
    );
    expect(calls, 1);
  });
}
