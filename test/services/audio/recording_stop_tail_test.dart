/// Regression test for the lost recording tail (ticket 22): audio spoken
/// before the hotkey release must reach the WAV even though the platform
/// delivers PCM with a latency. The fake recorder below models that latency:
/// captured buffers wait in flight until the test delivers them, and a stop
/// drops buffers still in flight, like macOS `removeTap` + `engine.stop`.
/// No real time passes: the tail wait is a hand-completed future (see
/// `recordingStopTailWaitProvider`), so the tests are deterministic.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:whispaste/services/audio_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RecordPlatform original;
  late _InFlightMicPlatform mic;
  late Completer<void> tail;
  Duration? requestedTail;

  ProviderContainer makeContainer() {
    final c = ProviderContainer(
      overrides: [
        recordingStopTailWaitProvider.overrideWithValue((d) {
          requestedTail = d;
          return tail.future;
        }),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  setUp(() {
    original = RecordPlatform.instance;
    mic = _InFlightMicPlatform();
    tail = Completer<void>();
    requestedTail = null;
    RecordPlatform.instance = mic;
    // The record package also talks to this channel directly (dispose).
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.llfbandit.record/messages'),
          (_) async => null,
        );
  });

  tearDown(() {
    RecordPlatform.instance = original;
  });

  test('the recorder keeps running for the whole tail and the audio still in '
      'the pipeline at release (a fading last word) reaches the WAV', () async {
    final container = makeContainer();
    final audio = container.read(audioServiceProvider.notifier);
    await audio.startRecording();

    final spoken = mic.capture(_chunk(8000));
    final fading = mic.capture(_chunk(40)); // quiet decay of the last word
    mic.deliverAll();
    final inFlightAtRelease = mic.capture(_chunk(25));

    // The user lets go of the hotkey here.
    final stopped = audio.stopRecording();
    await pumpEventQueue();
    expect(requestedTail, recordingStopTail);
    expect(mic.stopCalls, 0, reason: 'recorder must not stop during the tail');

    mic.deliverAll(); // pipeline latency elapses while the tail runs
    tail.complete();
    final path = await stopped;

    expect(mic.stopCalls, 1);
    final pcm = (await File(path!).readAsBytes()).sublist(44);
    expect(pcm, [...spoken, ...fading, ...inFlightAtRelease]);
  });

  test(
    'without the tail the in-flight audio would be lost (guards the fake)',
    () async {
      final container = makeContainer();
      final audio = container.read(audioServiceProvider.notifier);
      await audio.startRecording();
      mic.capture(_chunk(8000));
      mic.deliverAll();
      mic.capture(_chunk(25));

      final path = await audio.stopRecording(keepTail: false);

      expect((await File(path!).readAsBytes()).length - 44, _chunk(1).length);
    },
  );

  test(
    'abortStopTail ends the tail early and the recorder still stops',
    () async {
      final container = makeContainer();
      final audio = container.read(audioServiceProvider.notifier);
      await audio.startRecording();

      final stopped = audio.stopRecording();
      await pumpEventQueue();
      expect(audio.abortStopTail(), isTrue);
      await stopped;

      expect(mic.stopCalls, 1);
      expect(container.read(audioServiceProvider).isRecording, isFalse);
    },
  );
}

/// A 20 ms chunk of 16 kHz mono 16-bit PCM with a constant sample [level].
Uint8List _chunk(int level) {
  final data = ByteData(640);
  for (var i = 0; i < 320; i++) {
    data.setInt16(i * 2, level, Endian.little);
  }
  return data.buffer.asUint8List();
}

/// Fake `record` platform: captured chunks stay in flight until the test
/// delivers them; a stop drops what is still in flight.
class _InFlightMicPlatform extends RecordPlatform {
  final _inFlight = <Uint8List>[];
  StreamController<Uint8List>? _out;
  int stopCalls = 0;

  Uint8List capture(Uint8List chunk) {
    _inFlight.add(chunk);
    return chunk;
  }

  void deliverAll() {
    for (final c in _inFlight) {
      _out?.add(c);
    }
    _inFlight.clear();
  }

  @override
  Future<void> create(String recorderId) async {}

  @override
  Future<void> start(
    String recorderId,
    RecordConfig config, {
    required String path,
  }) async {}

  @override
  Future<bool> hasPermission(String recorderId, {bool request = true}) async =>
      true;

  @override
  Future<List<InputDevice>> listInputDevices(String recorderId) async =>
      const [];

  @override
  Future<bool> isEncoderSupported(
    String recorderId,
    AudioEncoder encoder,
  ) async => true;

  @override
  Future<Stream<Uint8List>> startStream(
    String recorderId,
    RecordConfig config,
  ) async {
    _out = StreamController<Uint8List>();
    return _out!.stream;
  }

  @override
  Future<String?> stop(String recorderId) async {
    stopCalls++;
    // Buffers not yet delivered are dropped, as the macOS tap does.
    _inFlight.clear();
    await _out?.close();
    _out = null;
    return null;
  }

  @override
  Future<void> cancel(String recorderId) async {
    await stop(recorderId);
  }

  @override
  Future<void> pause(String recorderId) async {}

  @override
  Future<void> resume(String recorderId) async {}

  @override
  Future<bool> isRecording(String recorderId) async => _out != null;

  @override
  Future<bool> isPaused(String recorderId) async => false;

  @override
  Future<Amplitude> getAmplitude(String recorderId) async =>
      Amplitude(current: -160, max: -160);

  @override
  Future<void> dispose(String recorderId) async {}

  @override
  Stream<RecordState> onStateChanged(String recorderId) =>
      const Stream<RecordState>.empty();

  @override
  void setOnConfigChanged(
    String recorderId,
    void Function(RecordConfig config)? handler,
  ) {}
}
