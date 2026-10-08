/// Headless transcription of a WAV file (`whispaste --transcribe-file`):
/// runs the app's own on-device transcription path without any UI and
/// reports load time, per-run inference time and real-time factor (RTF).
///
/// Used for latency benchmarks (`.github/workflows/headless-benchmark.yml`)
/// and scripting. It deliberately builds no pipeline of its own: the engine
/// is reached through the same [transcriberProvider] adapter and
/// [onDeviceEngineLifecycleProvider] the recording pipeline uses, so whisper
/// keeps its chunking, VAD, prompt and hallucination cleanup, and the result
/// gets the same whitespace cleanup ([collapseTranscriptWhitespace]) and —
/// with `--replacements` — the same text replacements as a dictation.
library;

import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/settings_enums.dart';
import '../../core/config/settings_provider.dart';
import '../model_download_service.dart' show findSttModel;
import '../replacements/text_replacement_matcher.dart';
import '../stt_engine_lifecycle_provider.dart';
import '../stt/whisper/whisper_isolate_engine.dart' show whisperEngineProvider;
import '../stt_parakeet/parakeet_model_registry.dart' show parakeetModelId;
import '../text_transforms.dart';
import '../transcription/transcriber.dart';

/// Usage text printed for an invalid headless command line.
const String headlessUsage = '''
Usage: whispaste --transcribe-file <file.wav> [options]

Transcribes a 16 kHz mono 16-bit PCM WAV without opening the app window.
  --engine whisper|parakeet  on-device engine (default: whisper)
  --model <id>               whisper model: whisper-small, whisper-medium,
                             whisper-large-v3-turbo (default: whisper-medium)
  --repeat <n>               transcribe n times after one model load (default: 1)
  --language <code>          language hint, e.g. en, de (default: auto)
  --gpu auto|enabled|disabled  GPU acceleration, as in the app settings;
                             disabled forces CPU (default: auto)
  --replacements             apply the text replacements from the app's data
  --json                     print a JSON timing report instead of the text
  --out <file>               also write the JSON timing report to <file>
''';

/// Parsed `--transcribe-file` command line.
class HeadlessTranscriptionOptions {
  const HeadlessTranscriptionOptions({
    required this.wavPath,
    this.engine = OnDeviceEngine.whisper,
    this.model,
    this.repeat = 1,
    this.language,
    this.applyReplacements = false,
    this.json = false,
    this.outPath,
    this.gpu = GpuAcceleration.auto,
  });

  final String wavPath;
  final OnDeviceEngine engine;

  /// Whisper model id from [sttModels]; `null` keeps the app default.
  final String? model;
  final int repeat;
  final String? language;
  final bool applyReplacements;
  final bool json;
  final String? outPath;

  /// Overrides the app's GPU acceleration setting for this run — lets a
  /// benchmark compare GPU against CPU on the same machine.
  final GpuAcceleration gpu;

  static bool isRequested(List<String> args) =>
      args.contains('--transcribe-file');

  /// Parses [args]; throws [FormatException] with a user-facing message.
  static HeadlessTranscriptionOptions parse(List<String> args) {
    String? wavPath;
    var engine = OnDeviceEngine.whisper;
    String? model;
    var repeat = 1;
    String? language;
    var applyReplacements = false;
    var json = false;
    String? outPath;
    var gpu = GpuAcceleration.auto;

    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      String value() {
        if (i + 1 >= args.length || args[i + 1].startsWith('--')) {
          throw FormatException('$arg needs a value');
        }
        return args[++i];
      }

      switch (arg) {
        case '--transcribe-file':
          wavPath = value();
        case '--engine':
          final name = value();
          engine = OnDeviceEngine.values.firstWhere(
            (e) => e.value == name,
            orElse: () => throw FormatException('unknown engine "$name"'),
          );
        case '--model':
          model = value();
          if (findSttModel(model) == null) {
            throw FormatException('unknown whisper model "$model"');
          }
        case '--repeat':
          final n = int.tryParse(value());
          if (n == null || n < 1) {
            throw const FormatException('--repeat needs a number >= 1');
          }
          repeat = n;
        case '--language':
          language = value();
        case '--replacements':
          applyReplacements = true;
        case '--json':
          json = true;
        case '--out':
          outPath = value();
        case '--gpu':
          final name = value();
          gpu = GpuAcceleration.values.firstWhere(
            (g) => g.value == name,
            orElse: () => throw FormatException('unknown --gpu value "$name"'),
          );
        default:
          throw FormatException('unknown option "$arg"');
      }
    }
    if (wavPath == null) {
      throw const FormatException('--transcribe-file needs a WAV path');
    }
    return HeadlessTranscriptionOptions(
      wavPath: wavPath,
      engine: engine,
      model: model,
      repeat: repeat,
      language: language,
      applyReplacements: applyReplacements,
      json: json,
      outPath: outPath,
      gpu: gpu,
    );
  }

  /// [base] with the on-device engine/model/language this run asks for.
  /// Live preview stays off: it only exists while a microphone streams.
  AppSettings applyTo(AppSettings base) => base.copyWith(
    sttProvider: SttProviderType.onDevice.value,
    sttEngine: engine.value,
    sttModel: model,
    sttLanguage: language,
    overlayShowLiveTranscript: false,
    gpuAcceleration: gpu.value,
  );
}

/// Re-wraps a 16 kHz mono 16-bit PCM WAV into the canonical 44-byte-header
/// layout the recorder writes (`wav_file_writer.dart`) and the app pipeline assumes,
/// dropping extra chunks (e.g. ffmpeg's `LIST`). Throws [FormatException]
/// for any other format — the pipeline does no resampling.
Uint8List canonicalPcm16MonoWav(Uint8List bytes) {
  String tag(int offset) => String.fromCharCodes(bytes, offset, offset + 4);
  if (bytes.length < 12 || tag(0) != 'RIFF' || tag(8) != 'WAVE') {
    throw const FormatException('not a RIFF/WAVE file');
  }
  final view = ByteData.sublistView(bytes);
  var formatOk = false;
  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final id = tag(offset);
    final size = view.getUint32(offset + 4, Endian.little);
    final body = offset + 8;
    if (id == 'fmt ' && body + 16 <= bytes.length) {
      formatOk =
          view.getUint16(body, Endian.little) == 1 &&
          view.getUint16(body + 2, Endian.little) == 1 &&
          view.getUint32(body + 4, Endian.little) == 16000 &&
          view.getUint16(body + 14, Endian.little) == 16;
      if (!formatOk) break;
    } else if (id == 'data') {
      if (!formatOk) break;
      final end = (body + size).clamp(body, bytes.length);
      return _wrapPcm(Uint8List.sublistView(bytes, body, end));
    }
    offset = body + size + (size.isOdd ? 1 : 0);
  }
  throw const FormatException(
    'expected a 16 kHz mono 16-bit PCM WAV '
    '(convert with: ffmpeg -i in -ar 16000 -ac 1 -c:a pcm_s16le out.wav)',
  );
}

Uint8List _wrapPcm(Uint8List pcm) {
  final header = ByteData(44)
    ..setUint32(0, 0x46464952, Endian.little) // RIFF
    ..setUint32(4, 36 + pcm.length, Endian.little)
    ..setUint32(8, 0x45564157, Endian.little) // WAVE
    ..setUint32(12, 0x20746D66, Endian.little) // 'fmt '
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little) // PCM
    ..setUint16(22, 1, Endian.little) // mono
    ..setUint32(24, 16000, Endian.little)
    ..setUint32(28, 32000, Endian.little) // byte rate
    ..setUint16(32, 2, Endian.little) // block align
    ..setUint16(34, 16, Endian.little)
    ..setUint32(36, 0x61746164, Endian.little) // data
    ..setUint32(40, pcm.length, Endian.little);
  return (BytesBuilder(copy: false)
        ..add(header.buffer.asUint8List())
        ..add(pcm))
      .toBytes();
}

/// One timed transcription of the file.
class HeadlessRun {
  const HeadlessRun({required this.transcribeMs});

  final int transcribeMs;
}

/// Result of a headless run; [toJson] is the `--json` report.
class HeadlessTranscriptionReport {
  const HeadlessTranscriptionReport({
    required this.engine,
    required this.model,
    required this.audioFile,
    required this.audioDurationMs,
    required this.loadMs,
    required this.runs,
    required this.totalMs,
    required this.transcript,
    this.backend = 'cpu',
    this.gpuDevice,
  });

  final String engine;
  final String model;
  final String audioFile;
  final int audioDurationMs;

  /// Model load incl. the engine's warmup — the cold-start cost of the
  /// first dictation.
  final int loadMs;
  final List<HeadlessRun> runs;

  /// Load plus every run.
  final int totalMs;
  final String transcript;

  /// Compute backend the engine ran on (`cpu`, `cuda`, `vulkan`, `metal`).
  final String backend;

  /// ggml GPU device whisper ran on, e.g. `CUDA0` or `Vulkan0` — tells an
  /// optional CUDA backend apart from Vulkan on the same NVIDIA card.
  final String? gpuDevice;

  double _rtf(int ms) => audioDurationMs == 0 ? 0 : ms / audioDurationMs;

  Map<String, Object?> toJson() {
    final sorted = runs.map((r) => r.transcribeMs).toList()..sort();
    final median = sorted[sorted.length ~/ 2];
    return {
      'engine': engine,
      'model': model,
      'platform': Platform.operatingSystem,
      'backend': backend,
      'gpuDevice': gpuDevice,
      'audioFile': audioFile,
      'audioDurationMs': audioDurationMs,
      'loadMs': loadMs,
      'transcribeMsMedian': median,
      'rtfMedian': _rtf(median),
      'totalMs': totalMs,
      'runs': [
        for (final r in runs)
          {'transcribeMs': r.transcribeMs, 'rtf': _rtf(r.transcribeMs)},
      ],
      'transcript': transcript,
    };
  }
}

class HeadlessTranscriptionException implements Exception {
  const HeadlessTranscriptionException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Loads the engine selected in [container]'s settings once, transcribes
/// [wavBytes] (canonical, see [canonicalPcm16MonoWav]) `options.repeat`
/// times and times each step with [clockMs] (milliseconds, monotonic).
///
/// [replacementRules] are applied only with `--replacements`.
Future<HeadlessTranscriptionReport> runHeadlessTranscription(
  ProviderContainer container,
  HeadlessTranscriptionOptions options,
  Uint8List wavBytes, {
  List<TextReplacementRule> replacementRules = const [],
  int Function()? clockMs,
}) async {
  final stopwatch = Stopwatch()..start();
  final now = clockMs ?? () => stopwatch.elapsedMilliseconds;
  final settings = await container.read(settingsProvider.future);
  final language = options.language ?? settings.sttLanguageCode;
  final lifecycle = container.read(onDeviceEngineLifecycleProvider);
  final transcriber = container.read(transcriberProvider);

  // Same order as a dictation: the engine counts as busy before the model
  // load, which keeps whisper's post-load self-benchmark from queueing in
  // front of the timed runs.
  lifecycle.notifyRecordingStarted();
  final start = now();
  try {
    await transcriber.prepare();
  } on TranscriberException catch (e) {
    throw HeadlessTranscriptionException('engine failed to load: ${e.message}');
  }
  final status = lifecycle.status;
  if (!status.isReady) {
    throw HeadlessTranscriptionException(
      'engine failed to load: ${status.errorMessage ?? 'not ready'}',
    );
  }
  final loadMs = now() - start;

  final runs = <HeadlessRun>[];
  var transcript = '';
  for (var i = 0; i < options.repeat; i++) {
    final runStart = now();
    final raw = await transcriber.transcribe(
      wavBytes,
      language: language.isEmpty ? 'auto' : language,
    );
    transcript = collapseTranscriptWhitespace(raw);
    if (options.applyReplacements) {
      transcript = applyTextReplacements(transcript, replacementRules);
    }
    runs.add(HeadlessRun(transcribeMs: now() - runStart));
    if (transcript.isEmpty) {
      throw const HeadlessTranscriptionException('transcription was empty');
    }
  }
  lifecycle.notifyTranscriptionCompleted();

  // Parakeet is CPU-only. A whisper engine that is not loaded means the
  // GPU load failed and the CPU fallback engine did the work.
  final whisper = options.engine == OnDeviceEngine.whisper
      ? container.read(whisperEngineProvider).status
      : null;
  final onGpu = whisper != null && whisper.isLoaded;

  return HeadlessTranscriptionReport(
    engine: options.engine.value,
    model: options.engine == OnDeviceEngine.parakeet
        ? parakeetModelId
        : settings.effectiveModelId,
    audioFile: options.wavPath,
    audioDurationMs: ((wavBytes.length - 44) / 32000 * 1000).round(),
    loadMs: loadMs,
    runs: runs,
    totalMs: now() - start,
    transcript: transcript,
    backend: onGpu ? whisper.backend.name : 'cpu',
    gpuDevice: onGpu ? whisper.gpuDevice : null,
  );
}
