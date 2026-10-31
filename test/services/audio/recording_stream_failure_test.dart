/// A microphone stream error in the middle of a recording (device unplugged,
/// driver reset) must not throw away the audio captured so far. The WAV is
/// finalised and kept, and the normal stop path hands it to transcription.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:whispaste/services/audio_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RecordPlatform original;
  late _FailingMicPlatform mic;

  setUp(() {
    original = RecordPlatform.instance;
    mic = _FailingMicPlatform();
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

  test('a PCM stream error keeps the WAV captured so far', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final audio = container.read(audioServiceProvider.notifier);

    await audio.startRecording();
    mic.speak(chunks: 20);
    mic.failStream();
    await _errorState(container);

    final status = container.read(audioServiceProvider);
    expect(status.captureState, AudioCaptureState.error);
    final kept = status.filePath;
    expect(kept, isNotNull, reason: 'the error state must point at the WAV');
    expect(
      File(kept!).existsSync(),
      isTrue,
      reason: 'the WAV captured before the device failure was deleted',
    );
    expect(File(kept).lengthSync(), greaterThan(44 + 640));
  });

  test('stopRecording after a stream error returns the kept WAV', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final audio = container.read(audioServiceProvider.notifier);

    await audio.startRecording();
    mic.speak(chunks: 20);
    mic.failStream();
    await _errorState(container);
    final kept = container.read(audioServiceProvider).filePath;

    final path = await audio.stopRecording();

    expect(path, isNotNull, reason: 'the pipeline gets no audio to transcribe');
    expect(path, kept);
    expect(File(path!).existsSync(), isTrue);
  });
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

/// Fake `record` platform. The test feeds 20 ms mic chunks with [speak] and
/// then [failStream] (the device going away mid-recording); the stream keeps
/// that order, so no wall-clock wait is needed between them.
class _FailingMicPlatform extends RecordPlatform {
  bool _recording = false;
  StreamController<Uint8List>? _out;

  void speak({required int chunks}) {
    for (var i = 0; i < chunks; i++) {
      _out!.add(Uint8List(640));
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
