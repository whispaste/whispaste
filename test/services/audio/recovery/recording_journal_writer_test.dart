/// The journal writer must never hold up the recorder start: begin runs in the
/// background, and end waits for the pending begin so the order always holds.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/audio/recovery/recording_journal.dart';

/// A journal whose begin waits for [gate], to simulate slow file IO.
class _GatedJournal extends RecordingJournal {
  _GatedJournal(super.directory);

  final Completer<void> gate = Completer<void>();
  int begins = 0;

  @override
  Future<void> begin({
    required String id,
    required DateTime startedAt,
    required String? wavPath,
  }) async {
    begins++;
    await gate.future;
    await super.begin(id: id, startedAt: startedAt, wavPath: wavPath);
  }
}

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('wp35-writer-');
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  test('beginInBackground returns before the journal write finishes', () async {
    final journal = _GatedJournal('${tmp.path}/journal');
    final writer = RecordingJournalWriter(journal: journal);

    writer.beginInBackground(
      id: 'rec-1',
      startedAt: DateTime(2026, 10, 17),
      wavPath: null,
    );

    // The gate is still closed, so the write has not completed. The call above
    // still returned: the start path does not wait for the disk.
    expect(journal.begins, 1);
    expect(File('${tmp.path}/journal/rec-1.json').existsSync(), isFalse);
    journal.gate.complete();
    await writer.endAndWait();
  });

  test(
    'endAndWait waits for a pending begin, so the entry is removed',
    () async {
      final journal = _GatedJournal('${tmp.path}/journal');
      final writer = RecordingJournalWriter(journal: journal);
      writer.beginInBackground(
        id: 'rec-2',
        startedAt: DateTime(2026, 10, 17),
        wavPath: null,
      );

      var ended = false;
      final end = writer.endAndWait().then((_) => ended = true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(ended, isFalse, reason: 'end must not run before begin completes');

      journal.gate.complete();
      await end;

      expect(ended, isTrue);
      final scan = await journal.scan();
      expect(
        scan.recordings,
        isEmpty,
        reason: 'begin then end leaves no entry',
      );
    },
  );

  test(
    'a failed begin is reported and does not throw from endAndWait',
    () async {
      final errors = <Object>[];
      final journal = _GatedJournal('${tmp.path}/journal');
      journal.gate.completeError(const FileSystemException('disk full'));
      final writer = RecordingJournalWriter(
        journal: journal,
        onError: errors.add,
      );
      writer.beginInBackground(
        id: 'rec-3',
        startedAt: DateTime(2026, 10, 17),
        wavPath: null,
      );

      await writer.endAndWait();

      expect(errors, hasLength(1));
    },
  );
}
