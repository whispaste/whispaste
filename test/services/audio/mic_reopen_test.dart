/// A stalled microphone stream is reopened once, silently, before the
/// dead-mic guard can end the dictation (#1784). Two faults lead there: the
/// platform stream delivers nothing (Linux, a Windows read that is not
/// re-armed), or the recorder stops by itself and says so only through its
/// state events (Windows `record_readercallback.cpp`). The reopen keeps the
/// WAV, the session and the configuration; a stop by the user always wins.
///
/// No real time passes: the stall checks are fired by hand through
/// `micStallTimerProvider`, and every wait is event-driven.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:whispaste/services/audio/mic_warmup_probe.dart';
import 'package:whispaste/services/audio_service.dart';
import 'package:whispaste/services/telemetry_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RecordPlatform original;
  late _StallingMicPlatform mic;
  late List<void Function(Timer)> stallChecks;

  ProviderContainer makeContainer() {
    final c = ProviderContainer(
      overrides: [
        micStallTimerProvider.overrideWithValue((interval, check) {
          expect(interval, micStallCheckInterval);
          stallChecks.add(check);
          return _NoTimer();
        }),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  /// Fires the latest capture's stall check [times] times.
  void fireStallChecks(int times) {
    for (var i = 0; i < times; i++) {
      stallChecks.last(_NoTimer());
    }
  }

  /// Checks needed until [micStallReopenAfter] has surely passed.
  final checksToStall =
      micStallReopenAfter.inMilliseconds ~/
          micStallCheckInterval.inMilliseconds +
      1;

  setUp(() {
    original = RecordPlatform.instance;
    mic = _StallingMicPlatform();
    stallChecks = [];
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

  test('a stream without any chunk is reopened once and the dictation goes '
      'on with the second stream', () async {
    final container = makeContainer();
    final audio = container.read(audioServiceProvider.notifier);
    await audio.startRecording();
    expect(mic.starts, 1);

    fireStallChecks(checksToStall - 1);
    await pumpEventQueue();
    expect(mic.starts, 1, reason: 'no reopen before the stall timeout');

    fireStallChecks(1);
    await _until(() => mic.starts == 2, 'the second stream');
    await _until(
      () => audio.micWarmup?.reopenRunning != null,
      'the reopen result',
    );

    expect(mic.configs.last, same(mic.configs.first));
    expect(audio.micWarmup?.reopenTrigger, MicReopenTrigger.stalled);
    expect(audio.micWarmup?.reopenRunning, isTrue);
    expect(container.read(audioServiceProvider).isRecording, isTrue);

    mic.speak(_chunk(3000), times: 10);
    await pumpEventQueue();
    final path = await audio.stopRecording(keepTail: false);

    final pcm = (await File(path!).readAsBytes()).sublist(44);
    expect(pcm.length, 10 * 640, reason: 'the second stream reached the WAV');
    expect(
      container.read(telemetrySessionAggregatorProvider).debugCounts[(
        'recording',
        'mic_reopen',
        'stalled_running',
      )],
      1,
    );
  });

  test('an unexpected recorder stop reopens the capture and keeps the audio '
      'already in the WAV', () async {
    final container = makeContainer();
    final audio = container.read(audioServiceProvider.notifier);
    await audio.startRecording();
    await mic.stateListened.future;

    final before = _chunk(1000);
    mic.speak(before, times: 5);
    await pumpEventQueue();
    // Windows after a read error: native stop, `stop` event, the PCM stream
    // stays open and silent.
    mic.nativeStop();

    await _until(() => mic.starts == 2, 'the second stream');
    final after = _chunk(2000);
    await _until(
      () => audio.micWarmup?.reopenRunning != null,
      'the reopen result',
    );
    mic.speak(after, times: 5);
    await pumpEventQueue();
    final path = await audio.stopRecording(keepTail: false);

    expect(audio.micWarmup?.reopenTrigger, MicReopenTrigger.platformStop);
    final pcm = (await File(path!).readAsBytes()).sublist(44);
    expect(pcm, [
      for (var i = 0; i < 5; i++) ...before,
      for (var i = 0; i < 5; i++) ...after,
    ]);
  });

  test('the reopen happens only once per recording', () async {
    final container = makeContainer();
    final audio = container.read(audioServiceProvider.notifier);
    await audio.startRecording();
    await mic.stateListened.future;

    fireStallChecks(checksToStall);
    await _until(
      () => audio.micWarmup?.reopenRunning != null,
      'the reopen result',
    );
    mic.nativeStop();
    fireStallChecks(checksToStall);
    await pumpEventQueue();

    expect(mic.starts, 2, reason: 'a second fault leaves it to the guard');
    await audio.stopRecording(keepTail: false);
  });

  test('our own stop is no fault and reopens nothing', () async {
    final container = makeContainer();
    final audio = container.read(audioServiceProvider.notifier);
    await audio.startRecording();
    await mic.stateListened.future;
    mic.speak(_chunk(500), times: 3);

    await audio.stopRecording(keepTail: false);
    fireStallChecks(checksToStall);
    await pumpEventQueue();

    expect(mic.starts, 1);
    expect(mic.isRecordingNow, isFalse);
  });

  test(
    'a stop by the user during the reopen wins: no stream stays open',
    () async {
      final container = makeContainer();
      final audio = container.read(audioServiceProvider.notifier);
      await audio.startRecording();

      final gate = mic.stopGate = Completer<void>();
      fireStallChecks(checksToStall);
      await _until(
        () => mic.stopCalls == 1,
        'the reopen stopping the recorder',
      );

      // The user stops while the reopen still waits for the recorder.
      final stopped = audio.stopRecording(keepTail: false);
      gate.complete();
      mic.stopGate = null;
      final path = await stopped;
      await pumpEventQueue();

      expect(path, isNotNull);
      expect(mic.starts, 1, reason: 'the reopen must not open a new stream');
      expect(mic.isRecordingNow, isFalse);
      expect(container.read(audioServiceProvider).isRecording, isFalse);
      expect(audio.micWarmup?.reopenRunning, isNull);
    },
  );
}

/// Turns the event loop until [done] holds. Event-driven: a loaded machine
/// only makes it slower; the bound only ends a real regression.
Future<void> _until(bool Function() done, String what) async {
  for (var i = 0; i < 200 && !done(); i++) {
    await pumpEventQueue();
  }
  expect(done(), isTrue, reason: 'never reached: $what');
}

/// A 20 ms chunk of 16 kHz mono 16-bit PCM with a constant sample [level].
Uint8List _chunk(int level) {
  final data = ByteData(640);
  for (var i = 0; i < 320; i++) {
    data.setInt16(i * 2, level, Endian.little);
  }
  return data.buffer.asUint8List();
}

class _NoTimer implements Timer {
  @override
  void cancel() {}

  @override
  bool get isActive => false;

  @override
  int get tick => 0;
}

/// Fake `record` platform. [speak] feeds chunks into the current stream,
/// [nativeStop] stops like `record_windows` after a read error: the state
/// turns to `stop` and is reported, the PCM stream is left open and silent.
class _StallingMicPlatform extends RecordPlatform {
  final _states = StreamController<RecordState>.broadcast();
  final Completer<void> stateListened = Completer<void>();
  StreamController<Uint8List>? _out;
  bool isRecordingNow = false;
  int starts = 0;
  int stopCalls = 0;
  final List<RecordConfig> configs = [];

  /// Holds a stop until the test completes it.
  Completer<void>? stopGate;

  void speak(Uint8List chunk, {required int times}) {
    for (var i = 0; i < times; i++) {
      _out?.add(chunk);
    }
  }

  void nativeStop() {
    isRecordingNow = false;
    _states.add(RecordState.stop);
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
    starts++;
    configs.add(config);
    _out = StreamController<Uint8List>();
    isRecordingNow = true;
    _states.add(RecordState.record);
    return _out!.stream;
  }

  @override
  Future<String?> stop(String recorderId) async {
    stopCalls++;
    await stopGate?.future;
    isRecordingNow = false;
    _states.add(RecordState.stop);
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
  Future<bool> isRecording(String recorderId) async => isRecordingNow;

  @override
  Future<bool> isPaused(String recorderId) async => false;

  @override
  Future<void> dispose(String recorderId) async {}

  @override
  Future<Amplitude> getAmplitude(String recorderId) async =>
      Amplitude(current: -160, max: -160);

  @override
  Stream<RecordState> onStateChanged(String recorderId) {
    if (!stateListened.isCompleted) stateListened.complete();
    return _states.stream;
  }

  @override
  void setOnConfigChanged(
    String recorderId,
    void Function(RecordConfig config)? handler,
  ) {}
}
