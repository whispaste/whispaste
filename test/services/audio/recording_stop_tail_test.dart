/// Regression test for the lost recording tail (ticket 22): audio spoken
/// before the hotkey release must reach the WAV even though the platform
/// delivers PCM with a latency. The fake recorder below models that latency:
/// a buffer captured at time t is only delivered at t + [_latency], and a
/// stop drops buffers still in flight, like macOS `removeTap` + `engine.stop`.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:whispaste/services/audio_service.dart';

const _latency = Duration(milliseconds: 150);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RecordPlatform original;
  late _DelayedMicPlatform mic;

  setUp(() {
    original = RecordPlatform.instance;
    mic = _DelayedMicPlatform(_latency);
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

  test('stopRecording keeps audio captured before the release that is still '
      'in flight', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final audio = container.read(audioServiceProvider.notifier);

    await audio.startRecording();
    expect(container.read(audioServiceProvider).isRecording, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 400));

    // The user lets go of the hotkey here.
    final released = DateTime.now();
    final spokenBytes = mic.bytesCapturedUntil(released);
    final path = await audio.stopRecording();

    expect(path, isNotNull);
    final pcmBytes = (await File(path!).readAsBytes()).length - 44;
    // One 20 ms chunk of slack for the capture timer's granularity.
    expect(
      pcmBytes,
      greaterThanOrEqualTo(spokenBytes - _DelayedMicPlatform.chunkBytes),
      reason:
          'the last ${_latency.inMilliseconds} ms before the release '
          'were still in the platform pipeline and got dropped',
    );
  });

  test(
    'abortStopTail ends the tail early and the recorder still stops',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final audio = container.read(audioServiceProvider.notifier);

      await audio.startRecording();
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final stopped = audio.stopRecording();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(audio.abortStopTail(), isTrue);
      await stopped;

      expect(container.read(audioServiceProvider).isRecording, isFalse);
    },
  );
}

/// Fake `record` platform: 20 ms mic chunks, each delivered after [latency],
/// dropped if the recorder stops before delivery.
class _DelayedMicPlatform extends RecordPlatform {
  _DelayedMicPlatform(this.latency);

  static const chunkBytes = 640; // 20 ms of 16 kHz mono 16-bit PCM

  final Duration latency;
  final _capturedAt = <DateTime>[];
  final _inFlight = <Timer>{};
  Timer? _mic;
  StreamController<Uint8List>? _out;

  int bytesCapturedUntil(DateTime t) =>
      _capturedAt.where((c) => !c.isAfter(t)).length * chunkBytes;

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
    _mic = Timer.periodic(const Duration(milliseconds: 20), (_) {
      _capturedAt.add(DateTime.now());
      final chunk = Uint8List(chunkBytes);
      late final Timer delivery;
      delivery = Timer(latency, () {
        _inFlight.remove(delivery);
        final out = _out;
        if (out != null && !out.isClosed) out.add(chunk);
      });
      _inFlight.add(delivery);
    });
    return _out!.stream;
  }

  @override
  Future<String?> stop(String recorderId) async {
    _mic?.cancel();
    _mic = null;
    // Buffers not yet delivered are dropped, as the macOS tap does.
    for (final timer in _inFlight) {
      timer.cancel();
    }
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
  Future<bool> isRecording(String recorderId) async => _mic != null;

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
