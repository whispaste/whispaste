/// Kill test for crash recovery: a child process writes a journaled recording
/// with the production WAV writer, the parent SIGKILLs it mid-recording, and
/// the audio written so far must be recoverable from the journal.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/audio/import/pcm_decoder.dart';
import 'package:whispaste/services/audio/recovery/recording_journal.dart';
import 'package:whispaste/services/stt/wav_header_repair.dart';

import '../../../test_helpers/dart_sdk.dart';

void main() {
  test(
    'audio written before a SIGKILL is recovered from the journal',
    () async {
      final tmp = await Directory.systemTemp.createTemp('wp35-kill-');
      addTearDown(() => tmp.delete(recursive: true));
      final journalDir = '${tmp.path}/journal';
      const childScript =
          'test/services/audio/recovery/support/kill_writer_child.dart';

      final child = await Process.start(resolveDartExecutable(), [
        'run',
        childScript,
        journalDir,
      ]);
      final ready = Completer<void>();
      final lines = child.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      final sub = lines.listen((line) {
        if (line == 'READY' && !ready.isCompleted) ready.complete();
      });
      addTearDown(sub.cancel);

      await ready.future.timeout(const Duration(seconds: 120));
      child.kill(ProcessSignal.sigkill);
      await child.exitCode;

      final scan = await RecordingJournal(journalDir).scan();
      expect(scan.skippedCorrupt, 0);
      expect(scan.recordings, hasLength(1));
      final recovered = scan.recordings.single;
      expect(recovered.id, 'rec-kill');

      final bytes = await File(recovered.wavPath!).readAsBytes();
      // The writer patches the length fields only on close, which never ran.
      final repaired = repairZeroedWavSizeFields(bytes) ?? bytes;
      final decoded = decodeWavBytes(repaired);
      expect(decoded.sampleRate, 16000);
      expect(decoded.samples.length, greaterThan(16000 * 0.5));
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
