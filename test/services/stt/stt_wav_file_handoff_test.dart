/// Hand-off of a recording from [SttServerStateNotifier] to the whisper
/// engine (#1665): with the WAV's path the engine reads the file itself, so
/// its worker never gets a copy of all bytes, and the transcript is the same
/// as for the bytes. A file that is gone or changed size falls back to the
/// bytes; an engine without [WavFileDecode] always gets the bytes.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/services/audio/pcm_wav_codec.dart';
import 'package:whispaste/services/hardware_info_service.dart' as hw;
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/path_service.dart' as paths;
import 'package:whispaste/services/stt/stt_bundle.dart';

/// The transcript is a fingerprint of the samples the engine actually read,
/// so "same transcript" means "same audio".
String _transcriptOf(Pcm16WavView pcm) {
  var hash = 0x811c9dc5;
  final bytes = pcm.pcmBytes(0, pcm.sampleCount);
  for (var i = 0; i < bytes.lengthInBytes; i++) {
    hash = ((hash ^ bytes.getUint8(i)) * 0x01000193) & 0xffffffff;
  }
  return 'samples ${pcm.sampleCount} fingerprint ${hash.toRadixString(16)}';
}

class _BytesOnlyEngine implements WhisperEngine {
  bool _loaded = false;

  /// Every call as (how the audio came, its sample count).
  final calls = <(String, int)>[];

  /// The calls for this test's recording ([_ownSamples]). The notifier's
  /// post-load warm-up and benchmark decode audio of other lengths, and the
  /// benchmark may start at any time.
  List<String> get ownCalls => [
    for (final (kind, samples) in calls)
      if (samples == _ownSamples) kind,
  ];

  @override
  WhisperEngineStatus get status =>
      WhisperEngineStatus(isLoaded: _loaded, backend: WhisperBackend.cpu);

  @override
  Future<void> load({required String modelPath, String? vadModelPath}) async {
    _loaded = true;
  }

  @override
  Future<String> transcribe(
    List<int> wavBytes, {
    String? language,
    String? prompt,
    bool vadEnabled = false,
    bool reducedThreads = false,
  }) async {
    calls.add(('bytes', Pcm16WavView(wavBytes).sampleCount));
    return _transcriptOf(Pcm16WavView(wavBytes));
  }

  @override
  Future<void> unload() async {
    _loaded = false;
  }
}

class _FileReadingEngine extends _BytesOnlyEngine implements WavFileDecode {
  @override
  Future<String> transcribeFile(
    String wavPath, {
    String? language,
    String? prompt,
    bool vadEnabled = false,
    bool reducedThreads = false,
    void Function(double fraction)? onProgress,
  }) async {
    calls.add(('file', Pcm16WavView.file(wavPath).sampleCount));
    return _transcriptOf(Pcm16WavView.file(wavPath));
  }
}

class _FakeSettingsNotifier extends SettingsNotifier {
  @override
  Future<AppSettings> build() async =>
      AppSettings.defaults.copyWith(sttModel: 'whisper-small');
}

class _FakeModelDownloadNotifier extends ModelDownloadNotifier {
  @override
  ModelDownloadState build() => const ModelDownloadState(downloadedModels: {});
}

/// A canonical WAV of [seconds] of varied speech-level PCM. With
/// [patchSizes] false the size fields stay zero, as after a crash before
/// the writer closed the file.
const int _ownSamples = 21920; // 1.37 s

Uint8List _wav({double seconds = 1.37, bool patchSizes = true}) {
  final samples = (seconds * 16000).round();
  final data = ByteData(44 + samples * 2);
  void tag(int offset, String t) {
    for (var i = 0; i < t.length; i++) {
      data.setUint8(offset + i, t.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  data.setUint32(4, patchSizes ? 36 + samples * 2 : 0, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, 16000, Endian.little);
  data.setUint32(28, 32000, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  data.setUint32(40, patchSizes ? samples * 2 : 0, Endian.little);
  for (var i = 0; i < samples; i++) {
    data.setInt16(44 + i * 2, (i * 7919 % 16001) - 8000, Endian.little);
  }
  return data.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('wp1665_handoff_');
    final model = findSttModel('whisper-small')?.filename ?? 'model.bin';
    await File(
      p.join(dir.path, model),
    ).writeAsBytes(Uint8List(11 * 1024 * 1024));
    paths.sttDirOverride = dir.path;
  });

  tearDown(() async {
    paths.sttDirOverride = null;
    await dir.delete(recursive: true);
  });

  Future<SttServerStateNotifier> readyNotifier(WhisperEngine engine) async {
    final container = ProviderContainer(
      overrides: [
        whisperEngineProvider.overrideWithValue(engine),
        settingsProvider.overrideWith(_FakeSettingsNotifier.new),
        modelDownloadProvider.overrideWith(_FakeModelDownloadNotifier.new),
        hw.gpuInfoProvider.overrideWith(
          (_) async =>
              const hw.GpuInfo(vendor: hw.GpuVendor.none, name: 'Test CPU'),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(settingsProvider.future);
    final notifier = container.read(localSttBundleProvider.notifier);
    await notifier.ensureRunning();
    expect(
      container.read(localSttBundleProvider).serverState,
      SttServerState.ready,
    );
    return notifier;
  }

  String writeWav(Uint8List wav) {
    final path = p.join(dir.path, 'recording.wav');
    File(path).writeAsBytesSync(wav);
    return path;
  }

  test(
    'a matching file goes to the engine as its path, same transcript',
    () async {
      final engine = _FileReadingEngine();
      final notifier = await readyNotifier(engine);
      final wav = _wav();
      final path = writeWav(wav);
      engine.calls.clear();

      final fromBytes = await notifier.transcribeBytesWithProgress(wav);
      final fromPath = await notifier.transcribeBytesWithProgress(
        wav,
        wavPath: path,
      );

      expect(engine.ownCalls, ['bytes', 'file']);
      expect(fromPath, fromBytes);
      expect(fromPath, contains('samples 21920'));
    },
  );

  test(
    'an unpatched header reads the same from the file as repaired bytes',
    () async {
      final engine = _FileReadingEngine();
      final notifier = await readyNotifier(engine);
      final wav = _wav(patchSizes: false);
      final path = writeWav(wav);
      engine.calls.clear();

      final fromBytes = await notifier.transcribeBytesWithProgress(wav);
      final fromPath = await notifier.transcribeBytesWithProgress(
        wav,
        wavPath: path,
      );

      expect(engine.ownCalls, ['bytes', 'file']);
      expect(fromPath, fromBytes);
    },
  );

  test('a file that is gone falls back to the bytes', () async {
    final engine = _FileReadingEngine();
    final notifier = await readyNotifier(engine);
    final wav = _wav();
    engine.calls.clear();

    final text = await notifier.transcribeBytesWithProgress(
      wav,
      wavPath: p.join(dir.path, 'missing.wav'),
    );

    expect(engine.ownCalls, ['bytes']);
    expect(text, contains('samples 21920'));
  });

  test('a file that changed size falls back to the bytes', () async {
    final engine = _FileReadingEngine();
    final notifier = await readyNotifier(engine);
    final wav = _wav();
    final path = writeWav(_wav(seconds: 2));
    engine.calls.clear();

    final text = await notifier.transcribeBytesWithProgress(wav, wavPath: path);

    expect(engine.ownCalls, ['bytes']);
    expect(text, contains('samples 21920'));
  });

  test('an engine that cannot read files gets the bytes', () async {
    final engine = _BytesOnlyEngine();
    final notifier = await readyNotifier(engine);
    final wav = _wav();
    final path = writeWav(wav);
    engine.calls.clear();

    final text = await notifier.transcribeBytesWithProgress(wav, wavPath: path);

    expect(engine.ownCalls, ['bytes']);
    expect(text, contains('samples 21920'));
  });

  test('transcribe(path) reads the file through the engine', () async {
    final engine = _FileReadingEngine();
    final notifier = await readyNotifier(engine);
    final path = writeWav(_wav());
    engine.calls.clear();

    await notifier.transcribe(path);

    expect(engine.ownCalls, ['file']);
  });
}
