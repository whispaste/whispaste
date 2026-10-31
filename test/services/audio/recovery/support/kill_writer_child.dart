/// Child process for `recording_kill_test.dart`: starts a journaled recording
/// with the production [WavFileWriter] and keeps appending chunks until the
/// parent kills it. Prints READY once audio has been written.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:whispaste/services/audio/recovery/recording_journal.dart';
import 'package:whispaste/services/audio/wav_file_writer.dart';

Future<void> main(List<String> args) async {
  final dir = args.single;
  final wavPath = '$dir/rec-kill.wav';
  await RecordingJournal(
    dir,
  ).begin(id: 'rec-kill', startedAt: DateTime.now(), wavPath: wavPath);
  final sink = await FilePcmSink.open(wavPath);
  final writer = WavFileWriter(
    sink: sink,
    sampleRate: 16000,
    channels: 1,
    bitsPerSample: 16,
  );
  final chunk = Uint8List(3200); // 100 ms of 16 kHz mono int16
  for (var i = 0; ; i++) {
    await writer.writeChunk(chunk);
    if (i == 5) stdout.writeln('READY');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
