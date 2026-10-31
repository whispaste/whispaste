/// Out-of-process GPU probe: before this process uses a GPU backend for the
/// first time, a child process runs the app's own headless transcription
/// (`whispaste --transcribe-file … --gpu enabled`) on a short generated tone.
/// Only a child that exits 0 and reports a GPU backend clears the GPU for
/// this key. A child that crashes, hangs or silently ran on CPU marks the key
/// as "GPU not usable": it is persisted, and the app runs on CPU until the
/// user asks for a retry.
///
/// Why: a native abort inside a GPU driver (Sentry 153865283, 155114205) ends
/// the whole process, so the in-process crash marker can only see it on the
/// next start and the crash loop breaker needs two strikes. A child process
/// takes the crash instead, and the main app is never exposed to it.
///
/// Key: backend, app version, OS version, GPU name, VRAM and driver version.
/// A driver update therefore runs a new probe. An unreadable driver version
/// is the key value `unknown`: it is one stable key, so it does not probe
/// again on every start (see [GpuProbeService.retry] for a manual re-run).
///
/// The probe never runs in a probe child (see [kGpuProbeChildEnv]) and not
/// under `flutter test`. The child prints [kGpuProbeStartedLine] as soon as it
/// enters the app. A child that never prints it (a sandbox refusing the
/// spawn, a loader failure before `main`) gives verdict `unknown`: the
/// caller keeps the in-process path with its crash marker. A child that
/// printed it and then crashed, hung or ran on CPU is a GPU failure. So a
/// probe that cannot run never sends the app to CPU.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../../core/logging/app_logger.dart';
import '../../hardware_info_service.dart'
    show GpuInfo, gpuDriverVersionForTelemetry;
import '../../model_download_service.dart' show findSttModel;

final _log = AppLogger('GpuProbe');

/// Set to `1` in the environment of the probe child. A process with it set
/// never probes (it is the probe), and reports its GPU backend as usable.
const String kGpuProbeChildEnv = 'WHISPASTE_GPU_PROBE_CHILD';

/// Line the probe child writes to stdout when it enters the app (see
/// `lib/main.dart`). Without it the child never got to the GPU code.
const String kGpuProbeStartedLine = 'WHISPASTE_GPU_PROBE_STARTED';

/// How long the child may run before it is killed and counted as hung. A
/// first-ever Vulkan shader compile can take tens of seconds, so this is
/// generous: a hang is rare, a false "unusable" is expensive (CPU until the
/// user retries).
const Duration kGpuProbeTimeout = Duration(seconds: 90);

/// Verdict for one GPU backend in this process.
enum GpuProbeVerdict {
  /// The child ran the GPU backend to the end. Use it in process.
  usable,

  /// The child crashed, hung or did not use the GPU. Use CPU.
  unusable,

  /// The probe could not run (no model, child could not start). Keep the
  /// in-process path; nothing is persisted.
  unknown,
}

/// What one probe child did, before it is mapped to a [GpuProbeVerdict].
enum GpuProbeStatus { ok, failed, unavailable }

class GpuProbeOutcome {
  const GpuProbeOutcome._(this.status, this.reason);

  const GpuProbeOutcome.ok(String backend) : this._(GpuProbeStatus.ok, backend);

  const GpuProbeOutcome.failed(String reason)
    : this._(GpuProbeStatus.failed, reason);

  const GpuProbeOutcome.unavailable(String reason)
    : this._(GpuProbeStatus.unavailable, reason);

  final GpuProbeStatus status;

  /// The backend name for [GpuProbeStatus.ok], else why the probe failed.
  final String reason;
}

/// Maps what a child did onto an outcome. Pure, so the rules are tested
/// without a process.
///
/// [exitCode] is `null` only when the child did not exit (it was killed on
/// [timedOut]). [engineBackend] is the `backend` field of the child's JSON
/// report (`cpu`, `vulkan`, `cuda`, `metal`), `null` when there is none.
/// [reachedApp] is `false` when the child never printed
/// [kGpuProbeStartedLine]: nothing was probed, whatever the exit was.
GpuProbeOutcome classifyProbeRun({
  required int? exitCode,
  required bool timedOut,
  required String? engineBackend,
  required bool reachedApp,
}) {
  if (!reachedApp) {
    return const GpuProbeOutcome.unavailable(
      'probe child did not start the app',
    );
  }
  if (timedOut) return const GpuProbeOutcome.failed('timed out');
  if (exitCode == null) {
    return const GpuProbeOutcome.failed('no exit code');
  }
  if (exitCode != 0) {
    return GpuProbeOutcome.failed('exit code ${formatProbeExitCode(exitCode)}');
  }
  if (engineBackend == null || engineBackend.isEmpty) {
    return const GpuProbeOutcome.failed('no backend in report');
  }
  if (engineBackend == 'cpu') {
    return const GpuProbeOutcome.failed('engine ran on CPU');
  }
  return GpuProbeOutcome.ok(engineBackend);
}

/// Windows reports a native abort as a large unsigned status (0xC0000409 for
/// FAST_FAIL), which Dart may show as a negative or huge number. Shown in hex
/// so the log matches the Windows error tables.
String formatProbeExitCode(int code) {
  final unsigned = code & 0xFFFFFFFF;
  return unsigned > 0xFFFF
      ? '0x${unsigned.toRadixString(16).toUpperCase()}'
      : '$code';
}

/// Identity of one GPU backend setup. [id] is the persisted map key.
class GpuProbeKey {
  const GpuProbeKey({
    required this.backend,
    required this.gpuName,
    required this.vramMB,
    required this.driverVersion,
    required this.appVersion,
    required this.osVersion,
  });

  final String backend;
  final String gpuName;
  final int? vramMB;

  /// Sanitized by [gpuDriverVersionForTelemetry]: a version string or
  /// `unknown`. It never contains the separator of [id].
  final String driverVersion;
  final String appVersion;
  final String osVersion;

  String get id => [
    backend,
    appVersion,
    osVersion,
    gpuName,
    vramMB ?? 0,
    driverVersion,
  ].join('|');
}

/// One persisted probe result.
class GpuProbeRecord {
  const GpuProbeRecord({
    required this.usable,
    required this.reason,
    required this.checkedAt,
  });

  factory GpuProbeRecord.fromJson(Map<String, Object?> json) => GpuProbeRecord(
    usable: json['usable'] as bool,
    reason: json['reason'] as String? ?? '',
    checkedAt: DateTime.parse(json['checkedAt'] as String),
  );

  final bool usable;
  final String reason;
  final DateTime checkedAt;

  Map<String, Object?> toJson() => {
    'usable': usable,
    'reason': reason,
    'checkedAt': checkedAt.toUtc().toIso8601String(),
  };
}

/// The verdict a stored record gives without a new run, or `null` when the
/// key has never been probed.
GpuProbeVerdict? verdictFromRecord(GpuProbeRecord? record) {
  if (record == null) return null;
  return record.usable ? GpuProbeVerdict.usable : GpuProbeVerdict.unusable;
}

/// JSON file of probe results, keyed by [GpuProbeKey.id]. A missing or
/// unreadable file is an empty store: the probe then simply runs again.
class GpuProbeStore {
  GpuProbeStore(this.file);

  final File file;

  Map<String, GpuProbeRecord> _readAll() {
    try {
      if (!file.existsSync()) return {};
      final raw = jsonDecode(file.readAsStringSync());
      if (raw is! Map) return {};
      // One malformed entry is dropped alone; a single bad record must not
      // hide the valid ones, or the next write would persist their loss.
      final all = <String, GpuProbeRecord>{};
      for (final entry in raw.entries) {
        try {
          if (entry.value is! Map) continue;
          all[entry.key as String] = GpuProbeRecord.fromJson(
            Map<String, Object?>.from(entry.value as Map),
          );
        } on Object catch (e) {
          _log.warning('GPU probe record ${entry.key} unreadable: $e');
        }
      }
      return all;
    } on Object catch (e) {
      _log.warning('GPU probe store unreadable, probing again: $e');
      return {};
    }
  }

  GpuProbeRecord? read(String id) => _readAll()[id];

  void write(String id, GpuProbeRecord record) {
    final all = _readAll()..[id] = record;
    _writeAll(all);
  }

  void remove(String id) {
    final all = _readAll();
    if (all.remove(id) != null) _writeAll(all);
  }

  void _writeAll(Map<String, GpuProbeRecord> all) {
    try {
      file.parent.createSync(recursive: true);
      final tmp = File('${file.path}.tmp');
      tmp.writeAsStringSync(
        jsonEncode({for (final e in all.entries) e.key: e.value.toJson()}),
        flush: true,
      );
      tmp.renameSync(file.path);
    } on FileSystemException catch (e) {
      _log.warning('GPU probe result not saved: $e');
    }
  }
}

/// Runs one probe child for [modelId] and reports what it did.
typedef GpuProbeRun =
    Future<GpuProbeOutcome> Function({
      required String modelId,
      required Duration timeout,
    });

/// Decides, runs and remembers the probe. One child run per key per process
/// at most; later callers share the same future.
/// Operating system on which the probe does not run (`Platform.operatingSystem`).
///
/// On macOS a failed, impossible or aborted probe must never lead to CPU, so
/// the probe could only ever log. A probe that cannot change the outcome adds
/// nothing and its child process would only add the sandbox-spawn risk. Metal
/// is a dynamically loaded module (`libggml-metal.so`), so a Metal crash is not
/// caught by the probe there; that is accepted, see ADR 0030.
const String kGpuProbeSkippedOs = 'macos';

class GpuProbeService {
  GpuProbeService({
    required this.store,
    required this.run,
    required this.appVersion,
    required this.osVersion,
    this.enabled = true,
    String? operatingSystem,
  }) : operatingSystem = operatingSystem ?? Platform.operatingSystem;

  final GpuProbeStore store;
  final GpuProbeRun run;
  final String appVersion;
  final String osVersion;

  /// The OS this service runs on; tests inject another value.
  final String operatingSystem;

  /// Whether the probe runs on this OS at all (not on [kGpuProbeSkippedOs]).
  bool get appliesHere => operatingSystem != kGpuProbeSkippedOs;

  /// `false` in the probe child and under `flutter test`: the verdict is then
  /// [GpuProbeVerdict.usable] without any run or write.
  final bool enabled;

  final Map<String, Future<GpuProbeVerdict>> _memo = {};

  GpuProbeKey keyFor({required GpuInfo gpu, required String backend}) =>
      GpuProbeKey(
        backend: backend,
        gpuName: gpu.name,
        vramMB: gpu.vramMB,
        driverVersion: gpuDriverVersionForTelemetry(gpu.driverVersion),
        appVersion: appVersion,
        osVersion: osVersion,
      );

  /// Verdict for [backend] on [gpu], probing with [modelId] if the key is new.
  Future<GpuProbeVerdict> verdict({
    required GpuInfo gpu,
    required String backend,
    required String modelId,
  }) {
    if (!enabled || !appliesHere) return Future.value(GpuProbeVerdict.usable);
    final key = keyFor(gpu: gpu, backend: backend);
    return _memo.putIfAbsent(key.id, () => _resolve(key, modelId));
  }

  Future<GpuProbeVerdict> _resolve(GpuProbeKey key, String modelId) async {
    final known = verdictFromRecord(store.read(key.id));
    if (known != null) return known;
    // A model the child cannot find would look like a GPU failure. Only a
    // model from the built-in catalog is probed.
    if (findSttModel(modelId) == null) {
      return GpuProbeVerdict.unknown;
    }
    final outcome = await run(modelId: modelId, timeout: kGpuProbeTimeout);
    switch (outcome.status) {
      case GpuProbeStatus.ok:
        store.write(
          key.id,
          GpuProbeRecord(
            usable: true,
            reason: outcome.reason,
            checkedAt: DateTime.now(),
          ),
        );
        _log.info('GPU probe ok for ${key.backend} (${key.gpuName})');
        return GpuProbeVerdict.usable;
      case GpuProbeStatus.failed:
        store.write(
          key.id,
          GpuProbeRecord(
            usable: false,
            reason: outcome.reason,
            checkedAt: DateTime.now(),
          ),
        );
        _log.warning(
          'GPU probe failed for ${key.backend} (${key.gpuName}): '
          '${outcome.reason} — using CPU',
        );
        return GpuProbeVerdict.unusable;
      case GpuProbeStatus.unavailable:
        _log.warning('GPU probe could not run: ${outcome.reason}');
        return GpuProbeVerdict.unknown;
    }
  }

  /// Forgets the stored result for [key] (the settings "retry" action) and
  /// lets the next [verdict] probe again.
  void retry(GpuProbeKey key) {
    store.remove(key.id);
    _memo.remove(key.id);
  }
}

/// Mono 16-bit PCM WAV of a quiet 440 Hz tone: the probe input. A tone (not
/// silence) so the engine reaches a real decode, not only its VAD gate.
Uint8List gpuProbeWav({
  int sampleRate = 16000,
  Duration duration = const Duration(seconds: 1),
}) {
  final samples = sampleRate * duration.inMilliseconds ~/ 1000;
  final dataLength = samples * 2;
  final data = ByteData(44 + dataLength);
  void ascii(int offset, String text) {
    for (var i = 0; i < text.length; i++) {
      data.setUint8(offset + i, text.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  data.setUint32(4, 36 + dataLength, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little); // PCM
  data.setUint16(22, 1, Endian.little); // mono
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  data.setUint32(40, dataLength, Endian.little);
  for (var i = 0; i < samples; i++) {
    final v = (math.sin(2 * math.pi * 440 * i / sampleRate) * 0.1 * 32767)
        .round();
    data.setInt16(44 + 2 * i, v, Endian.little);
  }
  return data.buffer.asUint8List();
}
