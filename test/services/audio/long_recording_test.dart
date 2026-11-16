/// LONG-REC (#181): a 60-minute recording loses no audio. A fake microphone
/// feeds one hour of PCM through the real `AudioService` and WAV writer; the
/// WAV must hold every second when the recording ends at the duration limit
/// and when the device fails at minute 45. Crash and quit are covered by
/// `recovery/recording_kill_test.dart` and `recovery/transcription_lifecycle_test.dart`.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:whispaste/services/audio_service.dart';

const _bytesPerSecond = 16000 * 2;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RecordPlatform original;
  late _FakeMicPlatform mic;

  setUp(() {
    original = RecordPlatform.instance;
    mic = _FakeMicPlatform();
    RecordPlatform.instance = mic;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.llfbandit.record/messages'),
          (_) async => null,
        );
  });

  tearDown(() {
    RecordPlatform.instance = original;
  });

  test('a 60-minute recording stops with all 3600 s in the WAV', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final audio = container.read(audioServiceProvider.notifier);

    await audio.startRecording();
    mic.speakSeconds(3600);
    final path = await audio.stopRecording(keepTail: false);

    expect(path, isNotNull);
    addTearDown(() => File(path!).deleteSync());
    expect(_pcmBytes(path!), 3600 * _bytesPerSecond);
    expect(_headerDataSize(path), 3600 * _bytesPerSecond);
  }, timeout: const Timeout(Duration(minutes: 4)));

  test('a device failure at minute 45 keeps the 45 minutes and the stop path '
      'hands them over', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final audio = container.read(audioServiceProvider.notifier);

    await audio.startRecording();
    mic.speakSeconds(45 * 60);
    mic.failStream();
    await _errorState(container);
    final kept = container.read(audioServiceProvider).filePath;
    expect(kept, isNotNull);

    final path = await audio.stopRecording();

    expect(path, kept);
    addTearDown(() => File(path!).deleteSync());
    expect(_pcmBytes(path!), 45 * 60 * _bytesPerSecond);
    expect(_headerDataSize(path), 45 * 60 * _bytesPerSecond);
  }, timeout: const Timeout(Duration(minutes: 4)));
}

int _pcmBytes(String path) => File(path).lengthSync() - 44;

int _headerDataSize(String path) {
  final raf = File(path).openSync();
  try {
    raf.setPositionSync(40);
    return ByteData.sublistView(raf.readSync(4)).getUint32(0, Endian.little);
  } finally {
    raf.closeSync();
  }
}

/// Completes once the service reports the capture error. Event-driven, so a
/// loaded test machine only makes it slower, never red; the timeout only
/// bounds a real regression.
Future<void> _errorState(ProviderContainer container) {
  final reached = Completer<void>();
  final sub = container.listen(audioServiceProvider, (_, next) {
    if (next.captureState == AudioCaptureState.error && !reached.isCompleted) {
      reached.complete();
    }
  }, fireImmediately: true);
  return reached.future
      .timeout(const Duration(seconds: 30))
      .whenComplete(sub.close);
}

/// Fake `record` platform. The test feeds one-second mic chunks with
/// [speakSeconds] and then [failStream] (the device going away
/// mid-recording); the stream keeps that order, so no wall-clock wait is
/// needed between them.
class _FakeMicPlatform extends RecordPlatform {
  bool _recording = false;
  StreamController<Uint8List>? _out;

  void speakSeconds(int seconds) {
    final second = Uint8List(_bytesPerSecond);
    for (var i = 0; i < seconds; i++) {
      _out!.add(second);
    }
  }

  void failStream() {
    _out?.addError(Exception('device lost'));
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
    _recording = true;
    return _out!.stream;
  }

  @override
  Future<String?> stop(String recorderId) async {
    _recording = false;
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
  Future<bool> isRecording(String recorderId) async => _recording;

  @override
  Future<bool> isPaused(String recorderId) async => false;

  @override
  Future<void> dispose(String recorderId) async {}

  @override
  Future<Amplitude> getAmplitude(String recorderId) async =>
      Amplitude(current: -160, max: -160);

  @override
  Stream<RecordState> onStateChanged(String recorderId) =>
      const Stream<RecordState>.empty();

  @override
  void setOnConfigChanged(
    String recorderId,
    void Function(RecordConfig config)? handler,
  ) {}
}
