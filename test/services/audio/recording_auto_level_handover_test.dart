/// The automatic level runs once on the finished WAV, before the path is
/// handed on (#1611): recognition, the saved file and "Anhören" all read the
/// leveled file. Also on the kept WAV of a stream failure, never on a
/// cancelled recording, never in the manual mode, and the platform's own
/// `autoGain` stays off.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/services/audio/wav_leveler.dart';
import 'package:whispaste/services/audio_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RecordPlatform original;
  late _QuietMicPlatform mic;
  late List<String> leveled;

  ProviderContainer makeContainer({AppSettings? settings}) {
    final c = ProviderContainer(
      overrides: [
        recordingStopTailWaitProvider.overrideWithValue((_) async {}),
        wavLevelerProvider.overrideWithValue((path) {
          leveled.add(path);
          return levelWavFile(path);
        }),
        if (settings != null)
          settingsProvider.overrideWith(() => _FixedSettings(settings)),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  setUp(() {
    original = RecordPlatform.instance;
    mic = _QuietMicPlatform();
    RecordPlatform.instance = mic;
    leveled = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.llfbandit.record/messages'),
          (_) async => null,
        );
  });

  tearDown(() {
    RecordPlatform.instance = original;
  });

  test('a stop hands on the leveled WAV, leveled exactly once', () async {
    final container = makeContainer();
    final audio = container.read(audioServiceProvider.notifier);

    await audio.startRecording();
    await mic.speakQuietly();
    final path = await audio.stopRecording();

    expect(path, isNotNull);
    expect(leveled, [path]);
    expect(mic.lastConfig?.autoGain, isFalse);
    final rms = _rms(File(path!).readAsBytesSync());
    // Raw speech bursts sit at about -40 dBFS; leveled they are about ten
    // times louder.
    expect(rms, greaterThan(_rawRms * 5));
    await File(path).delete();
  });

  test('the kept WAV of a stream failure is leveled once as well', () async {
    final container = makeContainer();
    final audio = container.read(audioServiceProvider.notifier);

    await audio.startRecording();
    await mic.speakQuietly();
    mic.failStream();
    await _errorState(container);
    final kept = container.read(audioServiceProvider).filePath;
    expect(leveled, [kept], reason: 'leveled before the path was published');

    final path = await audio.stopRecording();

    expect(path, kept);
    expect(leveled, hasLength(1));
    expect(_rms(File(path!).readAsBytesSync()), greaterThan(_rawRms * 5));
    await File(path).delete();
  });

  test('a cancelled recording is not leveled', () async {
    final container = makeContainer();
    final audio = container.read(audioServiceProvider.notifier);

    await audio.startRecording();
    await mic.speakQuietly();
    final path = await audio.stopRecording(keepTail: false);

    expect(leveled, isEmpty);
    if (path != null && File(path).existsSync()) await File(path).delete();
  });

  test('the manual mode never runs the automatic level', () async {
    final manual = AppSettings.defaults.copyWithSections(
      audioInput: AppSettings.defaults.audioInput.copyWith(
        autoLevel: false,
        inputGain: 2.0,
      ),
    );
    final container = makeContainer(settings: manual);
    await container.read(settingsProvider.future);
    final audio = container.read(audioServiceProvider.notifier);

    await audio.startRecording();
    await mic.speakQuietly();
    final path = await audio.stopRecording();

    expect(leveled, isEmpty);
    // The manual volume doubled the samples instead.
    expect(
      _rms(File(path!).readAsBytesSync()),
      closeTo(_rawRms * 2, _rawRms * 0.2),
    );
    await File(path).delete();
  });
}

/// RMS of the quiet take [_QuietMicPlatform.speakQuietly] produces.
final double _rawRms = _rms(
  Uint8List.fromList([...List<int>.filled(44, 0), ..._quietTake()]),
);

/// Six bursts of a 220 Hz tone at about -40 dBFS RMS with 200 ms of faint
/// noise before each, as 16 kHz mono 16-bit PCM.
Uint8List _quietTake() {
  final random = math.Random(7);
  final amplitude = 32768 * math.pow(10, -40 / 20) * math.sqrt2;
  final out = ByteData(6 * 8000 * 2);
  for (var b = 0; b < 6; b++) {
    for (var i = 0; i < 8000; i++) {
      final v = i < 3200
          ? random.nextInt(41) - 20
          : (amplitude * math.sin(2 * math.pi * 220 * i / 16000)).round();
      out.setInt16((b * 8000 + i) * 2, v, Endian.little);
    }
  }
  return out.buffer.asUint8List();
}

double _rms(Uint8List wav) {
  final view = ByteData.sublistView(wav, 44);
  final n = view.lengthInBytes ~/ 2;
  var sum = 0.0;
  for (var i = 0; i < n; i++) {
    final v = view.getInt16(i * 2, Endian.little);
    sum += v * v;
  }
  return math.sqrt(sum / n);
}

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

class _FixedSettings extends SettingsNotifier {
  _FixedSettings(this._settings);
  final AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;
}

/// Fake `record` platform that delivers one quiet take in 20 ms chunks.
class _QuietMicPlatform extends RecordPlatform {
  bool _recording = false;
  StreamController<Uint8List>? _out;
  RecordConfig? lastConfig;

  /// Feeds the take. The stream keeps the order, so a later stop or
  /// failure reaches the service only after every chunk.
  Future<void> speakQuietly() async {
    final take = _quietTake();
    for (var i = 0; i < take.length; i += 640) {
      _out!.add(Uint8List.sublistView(take, i, math.min(i + 640, take.length)));
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
    lastConfig = config;
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
