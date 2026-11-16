/// The automatic level rewrites the finished capture WAV in place (#1611):
/// louder speech, same header and length, no leftover copy, and any file it
/// cannot handle stays byte for byte as it was (no lost dictation).
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/audio/wav_file_writer.dart';
import 'package:whispaste/services/audio/speech_leveler.dart';
import 'package:whispaste/services/audio/wav_leveler.dart';

/// Speech-like PCM at about -40 dBFS with quiet gaps.
Uint8List _quietSpeech() {
  final random = math.Random(1);
  final amplitude = 32768 * math.pow(10, -40 / 20) * math.sqrt2;
  final data = BytesBuilder();
  final chunk = ByteData(2);
  for (var b = 0; b < 6; b++) {
    for (var i = 0; i < 8000; i++) {
      final v = i < 3200
          ? random.nextInt(41) - 20
          : (amplitude * math.sin(2 * math.pi * 220 * i / 16000)).round();
      chunk.setInt16(0, v, Endian.little);
      data.add(chunk.buffer.asUint8List());
    }
  }
  return data.toBytes();
}

Future<Uint8List> _wav(Uint8List pcm) async {
  final sink = BytesSink();
  final writer = WavFileWriter(
    sink: sink,
    sampleRate: 16000,
    channels: 1,
    bitsPerSample: 16,
  );
  await writer.writeChunk(pcm);
  await writer.close();
  return sink.takeBytes();
}

double _rms(Uint8List wav) {
  final view = ByteData.sublistView(wav, 44);
  var sum = 0.0;
  final n = view.lengthInBytes ~/ 2;
  for (var i = 0; i < n; i++) {
    final v = view.getInt16(i * 2, Endian.little);
    sum += v * v;
  }
  return math.sqrt(sum / n);
}

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('wav_leveler_test');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('quiet speech is raised in place, header and length kept', () async {
    final original = await _wav(_quietSpeech());
    final path = '${dir.path}/whispaste_1_ab.wav';
    File(path).writeAsBytesSync(original);

    final result = await levelWavFile(path);

    expect(result.error, isNull);
    expect(result.changed, isTrue);
    expect(result.boostDb, closeTo(20, 1));
    final leveled = File(path).readAsBytesSync();
    expect(leveled.length, original.length);
    expect(leveled.sublist(0, 44), original.sublist(0, 44));
    expect(_rms(leveled) / _rms(original), closeTo(10, 1.5));
    expect(File(levelingCopyPath(path)).existsSync(), isFalse);
    expect(dir.listSync(), hasLength(1));
  });

  test('a second run changes nothing: leveled audio stays leveled', () async {
    final path = '${dir.path}/whispaste_2_ab.wav';
    File(path).writeAsBytesSync(await _wav(_quietSpeech()));
    await levelWavFile(path);
    final once = File(path).readAsBytesSync();

    final again = await levelWavFile(path);

    expect(again.changed, isFalse);
    expect(File(path).readAsBytesSync(), once);
  });

  test('silence stays byte for byte as it was', () async {
    final original = await _wav(Uint8List(32000));
    final path = '${dir.path}/whispaste_3_ab.wav';
    File(path).writeAsBytesSync(original);

    final result = await levelWavFile(path);

    expect(result.changed, isFalse);
    expect(File(path).readAsBytesSync(), original);
  });

  test('a file that is not a mono 16-bit WAV is left alone', () async {
    final path = '${dir.path}/whispaste_4_ab.wav';
    final junk = Uint8List.fromList(List<int>.generate(4000, (i) => i % 251));
    File(path).writeAsBytesSync(junk);

    final result = await levelWavFile(path);

    expect(result.changed, isFalse);
    expect(result.error, isNotNull);
    expect(File(path).readAsBytesSync(), junk);
  });

  test('a missing file reports an error and creates nothing', () async {
    final path = '${dir.path}/whispaste_5_ab.wav';

    final result = await levelWavFile(path);

    expect(result.error, isNotNull);
    expect(dir.listSync(), isEmpty);
  });

  test('a refused write keeps the original audio', () async {
    final original = await _wav(_quietSpeech());
    final path = '${dir.path}/whispaste_6_ab.wav';
    File(path).writeAsBytesSync(original);
    // A directory where the copy should go makes writing the copy fail.
    Directory(levelingCopyPath(path)).createSync();

    final result = await levelWavFile(path);

    expect(result.changed, isFalse);
    expect(result.error, isNotNull);
    expect(File(path).readAsBytesSync(), original);
  });

  test('the copy keeps the capture-file pattern the sweeps rely on', () {
    expect(
      levelingCopyPath('/x/whispaste_1_ab.wav'),
      '/x/whispaste_1_ab.leveling.wav',
    );
  });

  test('a recording longer than one read chunk is leveled sample for sample '
      'as in one pass (#1642)', () async {
    // 48 s of quiet speech: 1.5 MB of PCM, more than the 1 MB the leveler
    // reads per step, with an odd final byte the leveler leaves alone.
    final pcm = BytesBuilder();
    for (var i = 0; i < 16; i++) {
      pcm.add(_quietSpeech());
    }
    pcm.addByte(0x11);
    final original = await _wav(pcm.toBytes());
    final path = '${dir.path}/whispaste_7_ab.wav';
    File(path).writeAsBytesSync(original);

    final result = await levelWavFile(path);

    final expected = Uint8List.fromList(original);
    final data = ByteData.sublistView(expected, 44);
    final plan = analyzeSpeechLevel(data);
    applyGainWithSoftLimit(data, plan.gain);
    expect(result.error, isNull);
    expect(result.changed, isTrue);
    expect(result.boostDb, plan.boostDb);
    expect(File(path).readAsBytesSync(), expected);
    expect(dir.listSync(), hasLength(1));
  });
}
