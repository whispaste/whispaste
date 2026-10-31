/// Replay benchmark for the during-recording live preview
/// (live-transcript-streaming). A benchmark, not a test: it lives outside
/// `test/`, is started only on purpose, and writes numbers, not pass/fail.
///
/// Each corpus WAV is fed in 40 ms blocks into [LiveTranscriptPreviewer] on a
/// SIMULATED audio clock. A trigger fires every 2 s of audio (the production
/// timer interval), and the decoder counts as busy in simulated time for the
/// measured wall-clock duration of each preview decode, so ticks that arrive
/// while a decode is still running are skipped, as the real timer would. After
/// the last block, the production drain cap (2 s) is applied, then one full
/// batch decode with VAD runs as the final reference.
///
/// Metrics (per file, then totals):
/// - decode p50/p95 (ms, wall clock of [WhisperFfiEngine.decodeLivePreview]);
/// - duty cycle (% of audio time the preview decoder is busy);
/// - CPU seconds per audio minute (process CPU during preview decodes) and
///   feed CPU per audio minute (time spent in [addPcmChunk]);
/// - word-to-display lag: decode end minus the end of the audio the decode
///   covered (p50/p95), and the expected word latency = half a tick + decode
///   (word-level audio timestamps are not available from the FFI decode, so
///   the per-word value is an expectation, not a measurement);
/// - retractions: words of the previous display that still lie inside the new
///   covered range but are not kept, in order, by the new display (LCS);
/// - preview WER: each display against the reference words of the audio range
///   it covers (reference words mapped by audio time, so pauses bias it equally
///   for every configuration);
/// - final-decode delay: time the final decode waits for a still running
///   preview decode, capped at the production previewDrainCap; plus the
///   final decode's own wall time.
///
/// Run (Mac, one run at a time, nice + timeout; corpus from make_corpus.sh):
///
/// ```sh
/// BENCH_LABEL=baseline nice -n 19 timeout 3000 \
///   ~/.claude/infrastructure/test-dispatch/wp-test.sh run <worktree> --host mac \
///   benchmarks/live_preview/replay_bench_test.dart
/// ```
///
/// Env (all optional): BENCH_LABEL, BENCH_CORPUS (default
/// `benchmarks/live_preview/corpus`), BENCH_FILTER (substring of file names),
/// BENCH_MODEL (default: the app's large-v3-turbo model), BENCH_LIB (required: the
/// libwhisper to load, e.g. .build/libwhisper/macos-build/bin/libwhisper.dylib), BENCH_VAD (default: bundled Silero VAD),
/// BENCH_OUT (default `benchmarks/live_preview/out/<label>.json`).
library;

// ignore_for_file: avoid_print — a measurement tool; stdout is the deliverable.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/core/config/punctuation_priming_prompts.dart';
import 'package:whispaste/services/stt/live_preview/live_transcript_previewer.dart';
import 'package:whispaste/services/stt/process_cpu_probe.dart';
import 'package:whispaste/services/stt/whisper/whisper_engine.dart';
import 'package:whispaste/services/stt/whisper/whisper_ffi_engine.dart';
import 'package:whispaste/services/transcription/transcript_seam.dart'
    show normalizeTranscriptWord;

const _bytesPerMs = 32; // 16 kHz, 16-bit mono
const _blockBytes = 1280; // 40 ms
const _tickMs = 2000; // production triggerInterval
const _drainCapMs = 2000; // production previewDrainCap

Map<String, String> get _env => Platform.environment;

String get _label => _env['BENCH_LABEL'] ?? 'unlabeled';

Uint8List _pcmOf(Uint8List wav) {
  // Walk the RIFF chunks to the `data` payload (the corpus has a plain
  // 44-byte header, but do not rely on it).
  var pos = 12;
  while (pos + 8 <= wav.length) {
    final id = String.fromCharCodes(wav.sublist(pos, pos + 4));
    final size = ByteData.sublistView(
      wav,
      pos + 4,
      pos + 8,
    ).getUint32(0, Endian.little);
    if (id == 'data') {
      final end = math.min(wav.length, pos + 8 + size);
      return Uint8List.sublistView(wav, pos + 8, end);
    }
    pos += 8 + size + (size.isOdd ? 1 : 0);
  }
  throw const FormatException('no data chunk');
}

List<String> _words(String text) => text
    .split(RegExp(r'\s+'))
    .map(normalizeTranscriptWord)
    .where((w) => w.isNotEmpty)
    .toList(growable: false);

int _levenshtein(List<String> a, List<String> b) {
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var prev = List<int>.generate(b.length + 1, (j) => j);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      cur[j] = math.min(
        math.min(prev[j] + 1, cur[j - 1] + 1),
        prev[j - 1] + cost,
      );
    }
    prev = cur;
  }
  return prev[b.length];
}

int _lcs(List<String> a, List<String> b) {
  var prev = List<int>.filled(b.length + 1, 0);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0);
    for (var j = 1; j <= b.length; j++) {
      cur[j] = a[i - 1] == b[j - 1]
          ? prev[j - 1] + 1
          : math.max(prev[j], cur[j - 1]);
    }
    prev = cur;
  }
  return prev[b.length];
}

double _percentile(List<double> values, double q) {
  if (values.isEmpty) return 0;
  final sorted = [...values]..sort();
  return sorted[((sorted.length - 1) * q).round()];
}

class _Display {
  _Display({
    required this.tickMs,
    required this.coveredFromMs,
    required this.decodeMs,
    required this.cpuMs,
    required this.text,
  }) : words = _words(text);

  final int tickMs;
  final int coveredFromMs;
  final double decodeMs;
  final double cpuMs;
  final String text;
  final List<String> words;

  /// Audio time covered by this display (ends at the tick).
  int get coveredToMs => tickMs;
}

/// Word index range of [ref] that a time range covers, mapped by audio time.
List<String> _refSlice(List<String> ref, int fromMs, int toMs, int audioMs) {
  if (audioMs <= 0 || ref.isEmpty) return const [];
  int idx(int ms) => (ref.length * ms / audioMs).round().clamp(0, ref.length);
  final from = idx(fromMs);
  return ref.sublist(from, math.max(from, idx(toMs)));
}

class _FileResult {
  _FileResult({
    required this.name,
    required this.audioMs,
    required this.displays,
    required this.previewEdits,
    required this.previewRefWords,
    required this.retracted,
    required this.drainWaitMs,
    required this.finalMs,
    required this.feedMs,
  });

  final String name;
  final int audioMs;
  final List<_Display> displays;
  final int previewEdits;
  final int previewRefWords;
  final int retracted;
  final int drainWaitMs;
  final double finalMs;
  final double feedMs;

  double get dutyPercent =>
      displays.fold<double>(0, (s, d) => s + d.decodeMs) / audioMs * 100;

  Map<String, Object> toJson() => {
    'file': name,
    'audioMs': audioMs,
    'decodes': displays.length,
    'decodeP50Ms': _percentile(displays.map((d) => d.decodeMs).toList(), .5),
    'decodeP95Ms': _percentile(displays.map((d) => d.decodeMs).toList(), .95),
    'dutyPercent': double.parse(dutyPercent.toStringAsFixed(2)),
    'cpuSecPerAudioMin': double.parse(
      (displays.fold<double>(0, (s, d) => s + d.cpuMs) /
              1000 /
              (audioMs / 60000))
          .toStringAsFixed(3),
    ),
    'feedMsPerAudioMin': double.parse(
      (feedMs / (audioMs / 60000)).toStringAsFixed(2),
    ),
    'lagP50Ms': _percentile(displays.map((d) => d.decodeMs).toList(), .5),
    'lagP95Ms': _percentile(displays.map((d) => d.decodeMs).toList(), .95),
    'expectedWordLatencyMeanMs': displays.isEmpty
        ? 0
        : displays.fold<double>(0, (s, d) => s + _tickMs / 2 + d.decodeMs) /
              displays.length,
    'retracted': retracted,
    'previewWer': previewRefWords == 0
        ? 0
        : double.parse((previewEdits / previewRefWords).toStringAsFixed(4)),
    'drainWaitMs': drainWaitMs,
    'finalDecodeMs': double.parse(finalMs.toStringAsFixed(1)),
  };
}

Future<_FileResult> _replay({
  required WhisperFfiEngine engine,
  required File wav,
  required String language,
  required bool vad,
}) async {
  final wavBytes = wav.readAsBytesSync();
  final pcm = _pcmOf(Uint8List.fromList(wavBytes));
  final audioMs = pcm.length ~/ _bytesPerMs;
  const probe = ProcessCpuProbe();

  var simMs = 0;
  var busyUntilMs = 0;
  // Filled by the decode closure for the decode that the current tick runs.
  double? decodeMs;
  double cpuMs = 0;
  var coveredFromMs = 0;
  String? text;
  final displays = <_Display>[];

  final previewer = LiveTranscriptPreviewer(
    decode: (samples) async {
      final cpu0 = probe.sample().cpuTime;
      final sw = Stopwatch()..start();
      final decoded = await engine.decodeLivePreview(
        samples,
        language: language,
      );
      sw.stop();
      cpuMs = (probe.sample().cpuTime - cpu0).inMicroseconds / 1000;
      decodeMs = sw.elapsedMicroseconds / 1000;
      coveredFromMs = simMs - samples.length ~/ 16;
      text = decoded;
      return decoded;
    },
    now: () => DateTime.fromMillisecondsSinceEpoch(simMs),
  );
  await engine.startLivePreview();
  previewer.start(armTimer: false);

  var feedUs = 0;
  var offset = 0;
  var nextTickMs = _tickMs;
  while (offset < pcm.length) {
    final end = math.min(pcm.length, offset + _blockBytes);
    final chunk = Uint8List.fromList(pcm.sublist(offset, end));
    final feedSw = Stopwatch()..start();
    previewer.addPcmChunk(chunk);
    feedUs += feedSw.elapsedMicroseconds;
    offset = end;
    simMs = offset ~/ _bytesPerMs;
    if (simMs < nextTickMs) continue;
    nextTickMs += _tickMs;
    if (simMs < busyUntilMs) continue; // decoder busy: the real timer skips too
    decodeMs = null;
    text = null;
    await previewer.onTriggerTick();
    final ms = decodeMs;
    final shown = text;
    if (ms == null || shown == null) continue;
    displays.add(
      _Display(
        tickMs: simMs,
        coveredFromMs: coveredFromMs,
        decodeMs: ms,
        cpuMs: cpuMs,
        text: shown,
      ),
    );
    busyUntilMs = simMs + ms.round();
  }
  previewer.dispose();
  await engine.stopLivePreview();

  // Final reference: one full batch decode, as after a real recording.
  final drainWaitMs = math.min(math.max(0, busyUntilMs - audioMs), _drainCapMs);
  final finalSw = Stopwatch()..start();
  final finalText = await engine.transcribe(
    wavBytes,
    language: language,
    prompt: punctuationPrimingPrompts[language],
    vadEnabled: vad,
  );
  finalSw.stop();
  final ref = _words(finalText);

  var edits = 0;
  var refWords = 0;
  var retracted = 0;
  for (var i = 0; i < displays.length; i++) {
    final d = displays[i];
    final slice = _refSlice(ref, d.coveredFromMs, d.coveredToMs, audioMs);
    edits += _levenshtein(d.words, slice);
    refWords += slice.length;
    if (i == 0) continue;
    final prev = displays[i - 1];
    // Words of the previous display that the new display still covers (by
    // audio time, proportional within the previous display's words).
    final span = prev.coveredToMs - prev.coveredFromMs;
    final kept = <String>[];
    for (var k = 0; k < prev.words.length; k++) {
      final t =
          prev.coveredFromMs + (span * (k + 0.5) / prev.words.length).round();
      if (t >= d.coveredFromMs) kept.add(prev.words[k]);
    }
    retracted += kept.length - _lcs(kept, d.words);
  }

  return _FileResult(
    name: p.basename(wav.path),
    audioMs: audioMs,
    displays: displays,
    previewEdits: edits,
    previewRefWords: refWords,
    retracted: retracted,
    drainWaitMs: drainWaitMs,
    finalMs: finalSw.elapsedMicroseconds / 1000,
    feedMs: feedUs / 1000,
  );
}

void main() {
  final modelPath =
      _env['BENCH_MODEL'] ??
      p.join(
        _env['HOME'] ?? '',
        'Library/Application Support/WhisPaste/models/stt/'
        'ggml-large-v3-turbo-q5_0.bin',
      );
  // Required: the libwhisper to load (no default, so no local path in source).
  final libraryPath = _env['BENCH_LIB'] ?? '';
  final vadPath =
      _env['BENCH_VAD'] ??
      p.join(
        Directory.current.path,
        'assets/models/vad/ggml-silero-v5.1.2.bin',
      );
  final corpusDir =
      _env['BENCH_CORPUS'] ??
      p.join(Directory.current.path, 'benchmarks/live_preview/corpus');
  final filter = _env['BENCH_FILTER'] ?? '';

  test('live preview replay benchmark', () async {
    final wavs =
        Directory(corpusDir)
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.wav'))
            .where((f) => p.basename(f.path).contains(filter))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    final engine = WhisperFfiEngine(
      libraryPath: libraryPath,
      backend: whisperBackendFromName(_env['BENCH_BACKEND'] ?? 'metal'),
    );
    await engine.load(modelPath: modelPath, vadModelPath: vadPath);
    addTearDown(engine.unload);

    // Warm-up: first decode pays one-off backend pipeline compilation.
    await engine.transcribe(
      wavs.first.readAsBytesSync(),
      language: 'de',
      vadEnabled: true,
    );

    final files = <Map<String, Object>>[];
    for (final wav in wavs) {
      final language = p.basename(wav.path).startsWith('en_') ? 'en' : 'de';
      final sw = Stopwatch()..start();
      final result = await _replay(
        engine: engine,
        wav: wav,
        language: language,
        vad: true,
      );
      print(
        '${result.name} audio=${result.audioMs}ms decodes=${result.displays.length} '
        'duty=${result.dutyPercent.toStringAsFixed(1)}% '
        'wer=${(result.previewEdits / math.max(1, result.previewRefWords)).toStringAsFixed(3)} '
        'retracted=${result.retracted} wall=${sw.elapsedMilliseconds}ms',
      );
      files.add(result.toJson());
    }

    final out =
        _env['BENCH_OUT'] ??
        p.join(
          Directory.current.path,
          'benchmarks/live_preview/out/$_label.json',
        );
    Directory(p.dirname(out)).createSync(recursive: true);
    File(out).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'label': _label,
        'rev': _gitRev(),
        'model': p.basename(modelPath),
        'files': files,
      }),
    );
    print('wrote $out');
  }, timeout: const Timeout(Duration(minutes: 90)));
}

String _gitRev() {
  final r = Process.runSync('git', ['rev-parse', '--short', 'HEAD']);
  return r.exitCode == 0 ? (r.stdout as String).trim() : 'unknown';
}
