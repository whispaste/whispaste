/// Short A/B comparison of the CUDA pack against Vulkan on this machine
/// (#1670).
///
/// The CUDA pack is not faster everywhere: on a GTX 1650 it measured 1.8 to
/// 2.4 times slower than the bundled Vulkan path, on an RTX 3060 Ti 30 to
/// 48 % faster. A card list would guess; this measures. Once the pack is
/// loaded on CUDA, `SttServerStateNotifier` transcribes the spoken reference
/// clip on the loaded CUDA engine and on a temporary Vulkan engine with the
/// same model, a few times each, interleaved, and keeps the faster path.
///
/// The result is stored per setup ([cudaAbKey]: GPU, VRAM, driver, app build,
/// pack id and model) in `cuda_ab.json` in the app data folder, so a normal
/// start does not measure again. A driver update, a new build, another pack
/// or another model measures once more. The file is machine-bound and never
/// exported.
///
/// When Vulkan wins, the pack stays installed but is not loaded
/// ([activeCudaPackDirFor] in `cuda_pack.dart`), and the settings row says so
/// and offers the removal. Nothing is deleted without the user's click.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/logging/app_logger.dart';
import '../../hardware_info_service.dart'
    show GpuInfo, gpuDriverVersionForTelemetry;
import '../../path_service.dart';
import 'gpu_probe.dart' show kGpuProbeChildEnv;

final _log = AppLogger('CudaAb');

/// Which compute path won the comparison.
enum CudaAbWinner { cuda, vulkan }

/// Vulkan has to be at least this much faster (median against median) before
/// the pack is set aside. Two runs per side carry some noise, and the user
/// downloaded the pack on purpose: a tie keeps CUDA. On the GTX 1650 Vulkan
/// was 45 to 60 % faster, far beyond this margin.
const double kCudaAbVulkanMargin = 0.10;

/// Measured runs per side after the warm-up. Interleaved (CUDA, Vulkan,
/// CUDA, Vulkan) so a clock or thermal drift hits both sides alike.
const int kCudaAbRuns = 2;

/// VRAM the temporary Vulkan context needs next to the loaded one. The
/// catalog's per-model budget (`sttModelVramMB`) is a conservative bound for
/// one model; a second context of the shipped quantised models measured
/// below 1 GiB (large-v3-turbo: 878 MiB on a GTX 1650, #1670).
const int kCudaAbSecondContextMb = 1024;

/// Median of [values]; for an even count the mean of the middle two.
double medianMs(List<int> values) {
  if (values.isEmpty) throw ArgumentError('no values');
  final sorted = [...values]..sort();
  final mid = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[mid].toDouble()
      : (sorted[mid - 1] + sorted[mid]) / 2;
}

/// The A/B decision. Vulkan wins only when its median is at least
/// [kCudaAbVulkanMargin] below the CUDA median; otherwise CUDA stays.
CudaAbWinner pickCudaAbWinner({
  required List<int> cudaMs,
  required List<int> vulkanMs,
}) {
  final cuda = medianMs(cudaMs);
  final vulkan = medianMs(vulkanMs);
  return vulkan <= cuda * (1 - kCudaAbVulkanMargin)
      ? CudaAbWinner.vulkan
      : CudaAbWinner.cuda;
}

/// Identity of the setup a comparison describes. Any change (another card,
/// driver update, new build, another pack or model) measures again.
String cudaAbKey({
  required GpuInfo gpu,
  required String appVersion,
  required String packId,
  required String modelId,
}) => [
  gpu.name,
  gpu.vramMB ?? 0,
  gpuDriverVersionForTelemetry(gpu.driverVersion),
  appVersion,
  packId,
  modelId,
].join('|');

/// One stored comparison.
@immutable
class CudaAbRecord {
  const CudaAbRecord({
    required this.winner,
    required this.measuredAt,
    this.cudaMedianMs,
    this.vulkanMedianMs,
    this.interrupted = false,
  });

  factory CudaAbRecord.fromJson(Map<String, Object?> json) => CudaAbRecord(
    winner: CudaAbWinner.values.byName(json['winner'] as String),
    measuredAt: DateTime.parse(json['measuredAt'] as String),
    cudaMedianMs: (json['cudaMedianMs'] as num?)?.toDouble(),
    vulkanMedianMs: (json['vulkanMedianMs'] as num?)?.toDouble(),
    interrupted: json['interrupted'] as bool? ?? false,
  );

  final CudaAbWinner winner;
  final DateTime measuredAt;
  final double? cudaMedianMs;
  final double? vulkanMedianMs;

  /// The run never finished: the app ended while it measured (a crash in the
  /// temporary engine, or a quit). Read as "keep CUDA" so a crash cannot
  /// repeat on every start; the next key change measures again.
  final bool interrupted;

  bool get vulkanFaster => winner == CudaAbWinner.vulkan;

  Map<String, Object?> toJson() => {
    'winner': winner.name,
    'measuredAt': measuredAt.toUtc().toIso8601String(),
    'cudaMedianMs': ?cudaMedianMs,
    'vulkanMedianMs': ?vulkanMedianMs,
    if (interrupted) 'interrupted': true,
  };
}

/// Marker written right before a run and removed when it ends. One that is
/// still on disk at the next start belongs to a run that never ended.
const _kPendingField = 'pending';

/// How many setups the file keeps. Older ones are dropped on write.
const _kMaxRecords = 8;

/// JSON file of comparisons keyed by [cudaAbKey]. A missing or unreadable
/// file is an empty store: the comparison then runs again.
class CudaAbStore {
  CudaAbStore(this.file);

  final File file;

  /// Every stored record, with a run left pending by an earlier process read
  /// as [CudaAbRecord.interrupted] (CUDA stays).
  Map<String, CudaAbRecord> readAll() {
    final raw = _readRaw();
    final all = <String, CudaAbRecord>{};
    for (final entry in raw.entries) {
      final value = entry.value;
      if (value is! Map) continue;
      try {
        if (value[_kPendingField] == true) {
          all[entry.key] = CudaAbRecord(
            winner: CudaAbWinner.cuda,
            measuredAt: DateTime.parse(value['startedAt'] as String),
            interrupted: true,
          );
          continue;
        }
        all[entry.key] = CudaAbRecord.fromJson(
          Map<String, Object?>.from(value),
        );
      } on Object catch (e) {
        _log.warning('CUDA comparison record unreadable: $e');
      }
    }
    return all;
  }

  /// Marks a run for [key] as started (see [CudaAbRecord.interrupted]).
  void markPending(String key, {DateTime? now}) => _update(
    (all) => all[key] = {
      _kPendingField: true,
      'startedAt': (now ?? DateTime.now()).toUtc().toIso8601String(),
    },
  );

  /// Removes the pending marker of a run that stopped early on purpose (a
  /// dictation started), so the next chance measures again.
  void clearPending(String key) => _update((all) {
    final value = all[key];
    if (value is Map && value[_kPendingField] == true) all.remove(key);
  });

  void write(String key, CudaAbRecord record) =>
      _update((all) => all[key] = record.toJson());

  Map<String, Object?> _readRaw() {
    try {
      if (!file.existsSync()) return {};
      final raw = jsonDecode(file.readAsStringSync());
      return raw is Map ? Map<String, Object?>.from(raw) : {};
    } on Object catch (e) {
      _log.warning('CUDA comparison file unreadable, measuring again: $e');
      return {};
    }
  }

  void _update(void Function(Map<String, Object?> all) change) {
    final all = _readRaw();
    change(all);
    // Insertion order is write order: keep the newest entries.
    while (all.length > _kMaxRecords) {
      all.remove(all.keys.first);
    }
    try {
      file.parent.createSync(recursive: true);
      final tmp = File('${file.path}.tmp');
      tmp.writeAsStringSync(jsonEncode(all), flush: true);
      tmp.renameSync(file.path);
    } on FileSystemException catch (e) {
      _log.warning('CUDA comparison not saved: $e');
    }
  }
}

/// The stored comparisons, read once (synchronously, like the pack scan: the
/// engine provider needs them before the first load) and updated in memory
/// when a run ends.
class CudaAbNotifier extends Notifier<Map<String, CudaAbRecord>> {
  CudaAbStore get store => ref.read(cudaAbStoreProvider);

  @override
  Map<String, CudaAbRecord> build() => store.readAll();

  void markPending(String key) => store.markPending(key);

  void clearPending(String key) => store.clearPending(key);

  void record(String key, CudaAbRecord record) {
    store.write(key, record);
    state = {...state, key: record};
  }
}

final cudaAbStoreProvider = Provider<CudaAbStore>(
  (ref) => CudaAbStore(File(p.join(appDataDir(), 'cuda_ab.json'))),
);

final cudaAbProvider =
    NotifierProvider<CudaAbNotifier, Map<String, CudaAbRecord>>(
      CudaAbNotifier.new,
    );

/// Whether this process may run the comparison at all: not in the GPU probe
/// child, not headless (`--transcribe-file` overrides it), not under
/// `flutter test`.
final cudaAbEnabledProvider = Provider<bool>(
  (ref) =>
      Platform.environment[kGpuProbeChildEnv] != '1' &&
      !Platform.environment.containsKey('FLUTTER_TEST'),
);

/// Why a comparison ended without a result.
enum CudaAbAbort {
  /// A dictation started or the engine went away; try again later.
  busy,

  /// The temporary engine did not come up on a Vulkan device.
  noVulkan,
}

/// Result of [measureCudaAb]: the timings, or why it stopped.
@immutable
class CudaAbMeasurement {
  const CudaAbMeasurement({
    this.cudaMs = const [],
    this.vulkanMs = const [],
    this.abort,
  });

  final List<int> cudaMs;
  final List<int> vulkanMs;
  final CudaAbAbort? abort;

  bool get complete => abort == null;
}

/// Runs the comparison through the given seams, so the order and the abort
/// rules are testable without a GPU.
///
/// 1. [prepareVulkan] loads the temporary Vulkan engine; it returns false
///    when no Vulkan device came up.
/// 2. One warm-up per side, not counted: the first inference on a fresh
///    context builds kernels and pipelines and would make either side look
///    slow.
/// 3. [runs] interleaved pairs: [timeCuda], then [timeVulkan], each the
///    milliseconds of one reference transcription.
///
/// [shouldStop] is checked before every step: a dictation or an engine swap
/// ends the run after the step in progress (a native inference cannot be
/// interrupted).
Future<CudaAbMeasurement> measureCudaAb({
  required Future<bool> Function() prepareVulkan,
  required Future<int> Function() timeCuda,
  required Future<int> Function() timeVulkan,
  required bool Function() shouldStop,
  int runs = kCudaAbRuns,
}) async {
  const busy = CudaAbMeasurement(abort: CudaAbAbort.busy);
  if (shouldStop()) return busy;
  if (!await prepareVulkan()) {
    return const CudaAbMeasurement(abort: CudaAbAbort.noVulkan);
  }
  final cuda = <int>[];
  final vulkan = <int>[];
  for (var i = -1; i < runs; i++) {
    if (shouldStop()) return busy;
    final c = await timeCuda();
    if (shouldStop()) return busy;
    final v = await timeVulkan();
    if (i < 0) continue; // warm-up pair
    cuda.add(c);
    vulkan.add(v);
  }
  return CudaAbMeasurement(cudaMs: cuda, vulkanMs: vulkan);
}
