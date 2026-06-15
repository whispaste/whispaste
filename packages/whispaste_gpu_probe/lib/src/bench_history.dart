/// Persistent benchmark history for the WhisPaste GPU-Probe live bench.
///
/// Every live transcription (single or part of a multi-model batch) is appended
/// as ONE JSON line to a JSONL file that lives next to the exe. The report
/// reads the whole file back and renders a sortable comparison table across
/// runs — so a beta tester can record once, fan the same speech through several
/// engine × model combos, and see which was fastest on their hardware over time.
///
/// JSONL (one independent JSON object per line) is chosen deliberately: appends
/// are atomic-enough for a single-process tool, a malformed/truncated tail line
/// never corrupts the earlier history, and the file stays diff- and grep-able.
library;

import 'dart:convert';
import 'dart:io';

/// Inference backends that run on the CPU. Everything else is treated as a
/// GPU/accelerator backend for the report's "fastest GPU vs CPU" highlight.
const Set<String> _cpuBackends = {'cpu', 'onnx-cpu'};

/// True when [backend] denotes a GPU/accelerator path (directcompute, cuda,
/// cuda12, vulkan, directml, …) rather than a plain CPU path.
///
/// Unknown/null backends are treated as non-GPU so they never win the GPU
/// highlight by accident.
bool isGpuBackend(String? backend) {
  if (backend == null || backend.isEmpty) return false;
  return !_cpuBackends.contains(backend);
}

/// One recorded benchmark run — a single engine × model transcription of one
/// audio clip, with its measured speed and outcome.
class BenchRun {
  const BenchRun({
    required this.timestamp,
    required this.engineId,
    required this.engineLabel,
    required this.backend,
    required this.outcome,
    this.modelId,
    this.modelLabel,
    this.durationMs,
    this.audioMs,
    this.realtimeFactor,
    this.transcribedText,
    this.version,
  });

  /// When the run completed.
  final DateTime timestamp;

  /// Engine id, e.g. `sherpa-onnx-cpu`.
  final String engineId;

  /// Human engine label, e.g. `sherpa-onnx · Whisper (ONNX, CPU)`.
  final String engineLabel;

  /// Inference backend tag (`cpu`, `directcompute`, `cuda`, …).
  final String backend;

  /// Outcome name (`ok`, `crashed`, `hung`, `skipped`, …).
  final String outcome;

  /// Model id the run used, if any.
  final String? modelId;

  /// Human model label, if known.
  final String? modelLabel;

  /// Engine processing time in milliseconds.
  final int? durationMs;

  /// Length of the recorded audio in milliseconds.
  final int? audioMs;

  /// Realtime factor (engine ms ÷ audio ms; lower is faster).
  final double? realtimeFactor;

  /// Transcription produced (the tester's own speech).
  final String? transcribedText;

  /// Tool version stamp at run time.
  final String? version;

  /// True when this run used a GPU/accelerator backend.
  bool get isGpu => isGpuBackend(backend);

  /// JSON object for one JSONL line / the report payload.
  Map<String, Object?> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'engineId': engineId,
    'engineLabel': engineLabel,
    'backend': backend,
    'outcome': outcome,
    if (modelId != null) 'modelId': modelId,
    if (modelLabel != null) 'modelLabel': modelLabel,
    if (durationMs != null) 'durationMs': durationMs,
    if (audioMs != null) 'audioMs': audioMs,
    if (realtimeFactor != null) 'realtimeFactor': realtimeFactor,
    if (transcribedText != null) 'transcribedText': transcribedText,
    if (version != null) 'version': version,
    'isGpu': isGpu,
  };

  /// Parses one history line. Returns null when the timestamp or required
  /// engine/backend/outcome fields are missing or malformed.
  static BenchRun? fromJson(Map<String, Object?> j) {
    final ts = j['timestamp'];
    final engineId = j['engineId'];
    final backend = j['backend'];
    final outcome = j['outcome'];
    if (ts is! String ||
        engineId is! String ||
        backend is! String ||
        outcome is! String) {
      return null;
    }
    final parsedTs = DateTime.tryParse(ts);
    if (parsedTs == null) return null;
    return BenchRun(
      timestamp: parsedTs,
      engineId: engineId,
      engineLabel: j['engineLabel'] is String
          ? j['engineLabel'] as String
          : engineId,
      backend: backend,
      outcome: outcome,
      modelId: j['modelId'] is String ? j['modelId'] as String : null,
      modelLabel: j['modelLabel'] is String ? j['modelLabel'] as String : null,
      durationMs: (j['durationMs'] as num?)?.toInt(),
      audioMs: (j['audioMs'] as num?)?.toInt(),
      realtimeFactor: (j['realtimeFactor'] as num?)?.toDouble(),
      transcribedText: j['transcribedText'] is String
          ? j['transcribedText'] as String
          : null,
      version: j['version'] is String ? j['version'] as String : null,
    );
  }
}

/// Append-only JSONL store for [BenchRun]s, backed by a single file.
class BenchHistory {
  BenchHistory(this.file);

  /// The backing JSONL file (created lazily on first append).
  final File file;

  /// Appends one run as a JSON line, creating the parent directory and file if
  /// needed. Never throws on a write error — the caller logs and continues.
  void append(BenchRun run) {
    final parent = file.parent;
    if (!parent.existsSync()) parent.createSync(recursive: true);
    file.writeAsStringSync(
      '${jsonEncode(run.toJson())}\n',
      mode: FileMode.append,
    );
  }

  /// Loads every parseable run, oldest first. Missing file → empty list.
  /// Blank and malformed lines are skipped so a truncated tail never breaks
  /// the rest of the history.
  List<BenchRun> load() {
    if (!file.existsSync()) return const [];
    final runs = <BenchRun>[];
    for (final line in file.readAsLinesSync()) {
      final t = line.trim();
      if (t.isEmpty) continue;
      try {
        final obj = jsonDecode(t);
        if (obj is Map<String, Object?>) {
          final run = BenchRun.fromJson(obj);
          if (run != null) runs.add(run);
        }
      } on FormatException {
        // Truncated or corrupt line — skip it, keep the rest.
      }
    }
    return runs;
  }
}
