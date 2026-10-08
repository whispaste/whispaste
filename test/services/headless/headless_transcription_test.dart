import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/services/headless/headless_transcription.dart';
import 'package:whispaste/services/replacements/text_replacement_matcher.dart';
import 'package:whispaste/services/stt/on_device_engine_lifecycle.dart';
import 'package:whispaste/services/stt/whisper/whisper_engine.dart';
import 'package:whispaste/services/stt/whisper/whisper_isolate_engine.dart'
    show whisperEngineProvider;
import 'package:whispaste/services/stt_engine_lifecycle_provider.dart';
import 'package:whispaste/services/transcription/transcriber.dart';

/// Builds a 16 kHz mono 16-bit PCM WAV with [extraChunk] (e.g. an ffmpeg
/// `LIST` chunk) between `fmt ` and `data`.
Uint8List _wav({
  int sampleRate = 16000,
  int channels = 1,
  int bitsPerSample = 16,
  int dataBytes = 32000,
  List<int> extraChunk = const [],
}) {
  final fmt = ByteData(24)
    ..setUint8(0, 0x66)
    ..setUint8(1, 0x6D)
    ..setUint8(2, 0x74)
    ..setUint8(3, 0x20)
    ..setUint32(4, 16, Endian.little)
    ..setUint16(8, 1, Endian.little)
    ..setUint16(10, channels, Endian.little)
    ..setUint32(12, sampleRate, Endian.little)
    ..setUint32(16, sampleRate * channels * bitsPerSample ~/ 8, Endian.little)
    ..setUint16(20, channels * bitsPerSample ~/ 8, Endian.little)
    ..setUint16(22, bitsPerSample, Endian.little);
  final dataHeader = ByteData(8)
    ..setUint8(0, 0x64)
    ..setUint8(1, 0x61)
    ..setUint8(2, 0x74)
    ..setUint8(3, 0x61)
    ..setUint32(4, dataBytes, Endian.little);
  final pcm = Uint8List(dataBytes);
  for (var i = 0; i < dataBytes; i++) {
    pcm[i] = i % 251;
  }
  final body = BytesBuilder()
    ..add(ascii.encode('WAVE'))
    ..add(fmt.buffer.asUint8List())
    ..add(extraChunk)
    ..add(dataHeader.buffer.asUint8List())
    ..add(pcm);
  final riffSize = ByteData(4)..setUint32(0, body.length, Endian.little);
  return (BytesBuilder()
        ..add(ascii.encode('RIFF'))
        ..add(riffSize.buffer.asUint8List())
        ..add(body.toBytes()))
      .toBytes();
}

/// An ffmpeg-style `LIST` chunk (as in the LibriSpeech benchmark sample).
final _listChunk = [
  ...ascii.encode('LIST'),
  4, 0, 0, 0, //
  ...ascii.encode('INFO'),
];

/// Fake clock the fake engine advances, so timings are deterministic.
class _Clock {
  int nowMs = 0;
}

class _FakeTranscriber implements Transcriber {
  _FakeTranscriber(
    this.clock, {
    this.loadMs = 0,
    this.inferMs = 0,
    this.text = 'hello world',
  });

  final _Clock clock;
  final int loadMs;
  final int inferMs;
  final String text;
  int prepareCalls = 0;
  final transcribedBytes = <List<int>>[];
  final languages = <String?>[];

  @override
  Future<void> prepare() async {
    prepareCalls++;
    clock.nowMs += loadMs;
  }

  @override
  Future<String> transcribe(List<int> wavBytes, {String? language}) async {
    transcribedBytes.add(wavBytes);
    languages.add(language);
    clock.nowMs += inferMs;
    return text;
  }

  @override
  void release() {}
}

class _FakeLifecycle implements OnDeviceEngineLifecycle {
  _FakeLifecycle({this.ready = true, this.error});

  final bool ready;
  final String? error;
  final events = <String>[];

  @override
  EngineLifecycleStatus get status =>
      EngineLifecycleStatus(isReady: ready, errorMessage: error);

  @override
  Future<void> ensureRunning() async {}

  @override
  Future<void> prewarm() async {}

  @override
  Future<void> stop() async => events.add('stop');

  @override
  void notifyRecordingStarted() => events.add('recordingStarted');

  @override
  void notifyRecordingStopped() => events.add('recordingStopped');

  @override
  void notifyTranscriptionCompleted() => events.add('transcriptionCompleted');
}

/// Only [status] is read by the headless run; everything else is unused.
class _FakeWhisperEngine implements WhisperEngine {
  _FakeWhisperEngine(this.status);

  @override
  final WhisperEngineStatus status;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FixedSettingsNotifier extends SettingsNotifier {
  _FixedSettingsNotifier(this._settings);

  final AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;
}

void main() {
  group('HeadlessTranscriptionOptions.parse', () {
    test('is requested only by --transcribe-file', () {
      expect(
        HeadlessTranscriptionOptions.isRequested(['--transcribe-file', 'a']),
        isTrue,
      );
      expect(HeadlessTranscriptionOptions.isRequested(['--toggle']), isFalse);
    });

    test('defaults to whisper, one run, plain-text output', () {
      final o = HeadlessTranscriptionOptions.parse([
        '--transcribe-file',
        'clip.wav',
      ]);
      expect(o.wavPath, 'clip.wav');
      expect(o.engine, OnDeviceEngine.whisper);
      expect(o.model, isNull);
      expect(o.repeat, 1);
      expect(o.language, isNull);
      expect(o.applyReplacements, isFalse);
      expect(o.json, isFalse);
      expect(o.outPath, isNull);
    });

    test('reads every flag', () {
      final o = HeadlessTranscriptionOptions.parse([
        '--transcribe-file',
        'clip.wav',
        '--engine',
        'parakeet',
        '--model',
        'whisper-small',
        '--repeat',
        '3',
        '--language',
        'de',
        '--replacements',
        '--json',
        '--out',
        'r.json',
        '--gpu',
        'disabled',
      ]);
      expect(o.engine, OnDeviceEngine.parakeet);
      expect(o.model, 'whisper-small');
      expect(o.repeat, 3);
      expect(o.language, 'de');
      expect(o.applyReplacements, isTrue);
      expect(o.json, isTrue);
      expect(o.outPath, 'r.json');
      expect(o.gpu, GpuAcceleration.disabled);
    });

    test('--gpu maps onto the app\'s GPU acceleration setting', () {
      HeadlessTranscriptionOptions parse(List<String> extra) =>
          HeadlessTranscriptionOptions.parse([
            '--transcribe-file',
            'a.wav',
            ...extra,
          ]);

      expect(
        parse([]).applyTo(AppSettings.defaults).behavior.gpuAcceleration,
        GpuAcceleration.auto.value,
      );
      expect(
        parse([
          '--gpu',
          'disabled',
        ]).applyTo(AppSettings.defaults).behavior.gpuAcceleration,
        GpuAcceleration.disabled.value,
      );
    });

    for (final bad in [
      ['--transcribe-file'],
      ['--transcribe-file', 'a.wav', '--engine', 'deepgram'],
      ['--transcribe-file', 'a.wav', '--repeat', '0'],
      ['--transcribe-file', 'a.wav', '--repeat', 'x'],
      ['--transcribe-file', 'a.wav', '--model', 'whisper-huge'],
      ['--transcribe-file', 'a.wav', '--bogus'],
      ['--transcribe-file', 'a.wav', '--gpu', 'cuda'],
    ]) {
      test('rejects ${bad.skip(2).join(' ')}', () {
        expect(
          () => HeadlessTranscriptionOptions.parse(bad),
          throwsFormatException,
        );
      });
    }
  });

  group('canonicalPcm16MonoWav', () {
    test('keeps a canonical 44-byte-header WAV byte-identical', () {
      final wav = _wav();
      expect(canonicalPcm16MonoWav(wav), wav);
    });

    test('drops extra chunks so the app pipeline sees its own WAV shape', () {
      final canonical = canonicalPcm16MonoWav(_wav(extraChunk: _listChunk));
      expect(canonical, _wav());
    });

    for (final entry in {
      'stereo': _wav(channels: 2),
      '44.1 kHz': _wav(sampleRate: 44100),
      '8-bit': _wav(bitsPerSample: 8),
      'not a WAV': Uint8List.fromList(List.filled(64, 7)),
    }.entries) {
      test('rejects ${entry.key} input', () {
        expect(() => canonicalPcm16MonoWav(entry.value), throwsFormatException);
      });
    }
  });

  group('runHeadlessTranscription', () {
    late _Clock clock;
    late _FakeLifecycle lifecycle;

    ProviderContainer containerWith(
      Transcriber transcriber, {
      AppSettings? settings,
      WhisperEngineStatus whisperStatus = const WhisperEngineStatus(
        isLoaded: true,
      ),
    }) {
      final container = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(
            () => _FixedSettingsNotifier(settings ?? AppSettings.defaults),
          ),
          transcriberProvider.overrideWithValue(transcriber),
          onDeviceEngineLifecycleProvider.overrideWithValue(lifecycle),
          whisperEngineProvider.overrideWithValue(
            _FakeWhisperEngine(whisperStatus),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    setUp(() {
      clock = _Clock();
      lifecycle = _FakeLifecycle();
    });

    HeadlessTranscriptionOptions options(List<String> extra) =>
        HeadlessTranscriptionOptions.parse([
          '--transcribe-file',
          'clip.wav',
          ...extra,
        ]);

    test('loads once, transcribes N times and reports load time and RTF '
        'per run', () async {
      final transcriber = _FakeTranscriber(clock, loadMs: 1200, inferMs: 500);
      final container = containerWith(transcriber);
      // 64000 PCM bytes = 2 s of 16 kHz mono 16-bit audio.
      final wav = _wav(dataBytes: 64000);

      final report = await runHeadlessTranscription(
        container,
        options(['--repeat', '3']),
        wav,
        clockMs: () => clock.nowMs,
      );

      expect(transcriber.prepareCalls, 1);
      expect(transcriber.transcribedBytes, hasLength(3));
      expect(transcriber.transcribedBytes.first, wav);
      expect(report.audioDurationMs, 2000);
      expect(report.loadMs, 1200);
      expect(report.runs.map((r) => r.transcribeMs), [500, 500, 500]);
      expect(report.toJson()['rtfMedian'], 0.25);
      expect(report.totalMs, 1200 + 3 * 500);
      expect(report.transcript, 'hello world');
    });

    test('marks the engine busy before loading, as a recording does, and '
        'reports completion afterwards', () async {
      final container = containerWith(_FakeTranscriber(clock));

      await runHeadlessTranscription(
        container,
        options([]),
        _wav(),
        clockMs: () => clock.nowMs,
      );

      expect(lifecycle.events, ['recordingStarted', 'transcriptionCompleted']);
    });

    test('applies the pipeline whitespace cleanup and, only when asked, the '
        'text replacements', () async {
      final transcriber = _FakeTranscriber(clock, text: ' teh\n\nfox  ');
      const rules = [
        TextReplacementRule(triggers: ['teh'], replacement: 'the'),
      ];

      final plain = await runHeadlessTranscription(
        containerWith(transcriber),
        options([]),
        _wav(),
        replacementRules: rules,
        clockMs: () => clock.nowMs,
      );
      final replaced = await runHeadlessTranscription(
        containerWith(transcriber),
        options(['--replacements']),
        _wav(),
        replacementRules: rules,
        clockMs: () => clock.nowMs,
      );

      expect(plain.transcript, 'teh fox');
      expect(replaced.transcript, 'the fox');
    });

    test('passes the requested language, else the settings language like '
        'the recording pipeline', () async {
      final transcriber = _FakeTranscriber(clock);
      await runHeadlessTranscription(
        containerWith(transcriber),
        options(['--language', 'de']),
        _wav(),
        clockMs: () => clock.nowMs,
      );
      await runHeadlessTranscription(
        containerWith(transcriber),
        options([]),
        _wav(),
        clockMs: () => clock.nowMs,
      );

      expect(transcriber.languages, [
        'de',
        AppSettings.defaults.sttLanguageCode.isEmpty
            ? 'auto'
            : AppSettings.defaults.sttLanguageCode,
      ]);
    });

    test(
      'reports the whisper backend and the ggml GPU device it ran on',
      () async {
        final report = await runHeadlessTranscription(
          containerWith(
            _FakeTranscriber(clock),
            whisperStatus: const WhisperEngineStatus(
              isLoaded: true,
              backend: WhisperBackend.cuda,
              gpuDevice: 'CUDA0',
            ),
          ),
          options([]),
          _wav(),
          clockMs: () => clock.nowMs,
        );

        expect(report.toJson()['backend'], 'cuda');
        expect(report.toJson()['gpuDevice'], 'CUDA0');
      },
    );

    test('reports cpu when the GPU engine did not load (CPU fallback) and '
        'for parakeet', () async {
      final fallback = await runHeadlessTranscription(
        containerWith(
          _FakeTranscriber(clock),
          whisperStatus: const WhisperEngineStatus(
            isLoaded: false,
            backend: WhisperBackend.vulkan,
            gpuDevice: 'Vulkan0',
          ),
        ),
        options([]),
        _wav(),
        clockMs: () => clock.nowMs,
      );
      final parakeet = await runHeadlessTranscription(
        containerWith(_FakeTranscriber(clock)),
        options(['--engine', 'parakeet']),
        _wav(),
        clockMs: () => clock.nowMs,
      );

      expect(fallback.toJson()['backend'], 'cpu');
      expect(fallback.toJson()['gpuDevice'], isNull);
      expect(parakeet.toJson()['backend'], 'cpu');
    });

    test('fails with the engine error when prepare leaves it not ready', () {
      lifecycle = _FakeLifecycle(ready: false, error: 'model file not found');
      final container = containerWith(_FakeTranscriber(clock));

      expect(
        runHeadlessTranscription(
          container,
          options([]),
          _wav(),
          clockMs: () => clock.nowMs,
        ),
        throwsA(
          isA<HeadlessTranscriptionException>().having(
            (e) => e.message,
            'message',
            contains('model file not found'),
          ),
        ),
      );
    });

    test('fails on an empty transcript instead of reporting a fast run', () {
      final container = containerWith(_FakeTranscriber(clock, text: ' \n '));

      expect(
        runHeadlessTranscription(
          container,
          options([]),
          _wav(),
          clockMs: () => clock.nowMs,
        ),
        throwsA(isA<HeadlessTranscriptionException>()),
      );
    });
  });

  group('HeadlessTranscriptionReport.toJson', () {
    test('carries the timings and their medians', () {
      const report = HeadlessTranscriptionReport(
        engine: 'whisper',
        model: 'whisper-small',
        audioFile: 'clip.wav',
        audioDurationMs: 2000,
        loadMs: 900,
        runs: [
          HeadlessRun(transcribeMs: 600),
          HeadlessRun(transcribeMs: 400),
          HeadlessRun(transcribeMs: 500),
        ],
        totalMs: 2400,
        transcript: 'hello',
      );

      final json = report.toJson();

      expect(json['engine'], 'whisper');
      expect(json['model'], 'whisper-small');
      expect(json['audioDurationMs'], 2000);
      expect(json['loadMs'], 900);
      expect(json['totalMs'], 2400);
      expect(json['transcribeMsMedian'], 500);
      expect(json['rtfMedian'], 0.25);
      expect(json['runs'], [
        {'transcribeMs': 600, 'rtf': 0.3},
        {'transcribeMs': 400, 'rtf': 0.2},
        {'transcribeMs': 500, 'rtf': 0.25},
      ]);
      expect(json['transcript'], 'hello');
      expect(json['platform'], isA<String>());
      // Round-trips through JSON (no non-encodable values).
      expect(jsonDecode(jsonEncode(json)), json);
    });
  });
}
