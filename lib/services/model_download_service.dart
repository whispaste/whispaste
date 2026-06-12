/// Model download service — manages downloading STT models and the
/// whisper-server binary from HuggingFace and GitHub with progress,
/// SHA256 verification, and resume support.
library;

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../core/config/quality_tier.dart';
import '../core/config/settings_provider.dart';
import '../core/logging/app_logger.dart';

// Re-export QualityTier so existing import sites (e.g. tests) that use
// `model_download_service.dart` as the source continue to resolve without
// changes.
export '../core/config/quality_tier.dart' show QualityTier;
import 'file_verification_service.dart';
import 'hardware_info_service.dart' as hw;
import 'http_model_fetcher.dart';
import 'path_service.dart';
import 'tmp_reaper.dart';
import 'whisper_server_downloader.dart';
import 'whisper_server_manifest.dart';

final _log = AppLogger('Download');

// ---------------------------------------------------------------------------
// Model registry — single source of truth for all downloadable assets
// ---------------------------------------------------------------------------

/// Metadata for a downloadable STT model.
class SttModelInfo {
  const SttModelInfo({
    required this.id,
    required this.label,
    required this.filename,
    required this.sizeBytes,
    required this.url,
    required this.sha256,
  });

  final String id;
  final String label;
  final String filename;
  final int sizeBytes;
  final String url;
  final String sha256;

  String get sizeLabel {
    if (sizeBytes >= 1024 * 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    return '${(sizeBytes / (1024 * 1024)).round()} MB';
  }
}

/// All STT models the app exposes to the user (quantized, from HuggingFace
/// whisper.cpp).
///
/// One entry per [QualityTier]: `whisper-small` (Compact), `whisper-medium`
/// (Balanced), `whisper-large-v3-turbo` (Premium). Legacy IDs from earlier
/// versions (`whisper-tiny`, `whisper-base`, `whisper-large-v3`) are
/// rewritten on settings load by `_migrateModelId` in `settings_sections.dart`.
const List<SttModelInfo> sttModels = [
  SttModelInfo(
    id: 'whisper-small',
    label: 'Small',
    filename: 'ggml-small-q5_1.bin',
    sizeBytes: 190085487,
    url:
        'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small-q5_1.bin',
    sha256: 'ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb',
  ),
  SttModelInfo(
    id: 'whisper-medium',
    label: 'Medium',
    filename: 'ggml-medium-q5_0.bin',
    sizeBytes: 539212467,
    url:
        'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium-q5_0.bin',
    sha256: '19fea4b380c3a618ec4723c3eef2eb785ffba0d0538cf43f8f235e7b3b34220f',
  ),
  SttModelInfo(
    id: 'whisper-large-v3-turbo',
    label: 'Large v3 Turbo',
    filename: 'ggml-large-v3-turbo-q5_0.bin',
    sizeBytes: 574041195,
    url:
        'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin',
    sha256: '394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2',
  ),
];

/// Looks up a model by ID. Returns null if not found.
SttModelInfo? findSttModel(String id) {
  for (final m in sttModels) {
    if (m.id == id) return m;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Quality Tiers — user-facing abstraction over raw model names
// ---------------------------------------------------------------------------

// QualityTier is defined in lib/core/config/quality_tier.dart and
// re-exported above so all existing import sites continue to resolve.

/// Performance level of a quality tier based on real-time benchmark.
/// Used to determine UI display (info messages) and tier recommendations.
enum TierPerformance {
  /// Fast: benchmark RTF < 0.3 - excellent real-time performance.
  fast,

  /// Moderate: benchmark RTF 0.3-0.8 - good balance, slight delay.
  moderate,

  /// Slow: benchmark RTF > 0.8 - noticeable processing time.
  slow,

  /// No benchmark data yet - use VRAM fallback for recommendations.
  unmeasured,
}

/// Returns the model for [tier]. One model per tier — see [sttModels].
List<SttModelInfo> modelsForTier(QualityTier tier) {
  final id = switch (tier) {
    QualityTier.compact => 'whisper-small',
    QualityTier.balanced => 'whisper-medium',
    QualityTier.premium => 'whisper-large-v3-turbo',
  };
  return [sttModels.firstWhere((m) => m.id == id)];
}

/// Returns the single best model for [tier].
SttModelInfo bestModelForTier(QualityTier tier) => modelsForTier(tier).first;

/// Returns the tier a model belongs to, or null if unknown.
QualityTier? tierForModel(String modelId) {
  for (final tier in QualityTier.values) {
    if (modelsForTier(tier).any((m) => m.id == modelId)) return tier;
  }
  return null;
}

/// Auto-recommend a tier based on GPU capabilities.
///
/// Thresholds include conservative safety margins because:
/// - NVIDIA reports total VRAM, but OS overhead (~200-500MB), CUDA runtime,
///   and concurrent GPU processes consume part of it. Usable VRAM is ~70% of
///   reported.
/// - Intel/AMD integrated GPUs report shared system RAM as "VRAM" (e.g. 4-16GB),
///   but actual GPU-accessible memory is much smaller and shared with the CPU.
///   Conservative multipliers are applied.
/// - Apple Silicon has unified memory where "VRAM" = system RAM — generous
///   thresholds apply.
QualityTier recommendTier(int vramMB, {hw.GpuVendor? vendor}) {
  // Apple Silicon — unified memory, generous limits.
  if (vendor == hw.GpuVendor.apple) {
    if (vramMB >= 4096) return QualityTier.premium;
    if (vramMB >= 2048) return QualityTier.balanced;
    return QualityTier.compact;
  }

  // NVIDIA dedicated GPU — total VRAM * 0.70 = conservative usable estimate.
  // whisper-large-v3-turbo (2600MB) → needs ~3715MB reported (÷0.70).
  // whisper-medium (1500MB) → needs ~2150MB reported.
  if (vendor == hw.GpuVendor.nvidia) {
    if (vramMB >= 3715) return QualityTier.premium;
    if (vramMB >= 2150) return QualityTier.balanced;
    return QualityTier.compact;
  }

  // Intel/AMD integrated GPUs — shared memory is unreliable.
  // Treat reported "VRAM" as upper bound, apply aggressive safety margin.
  // whisper-large-v3-turbo only if ≥12GB reported (very safe for integrated).
  if (vramMB >= 12288) return QualityTier.premium;
  if (vramMB >= 4096) return QualityTier.balanced;
  return QualityTier.compact;
}

/// Returns the performance level of [tier] based on benchmark RTF data.
/// Falls back to VRAM-based estimation if no benchmark available.
TierPerformance tierPerformance(
  QualityTier tier,
  hw.GpuInfo gpu, {
  Map<QualityTier, double>? benchmarkRtf,
}) {
  // If we have benchmark data, use it directly.
  if (benchmarkRtf != null && benchmarkRtf.containsKey(tier)) {
    final rtf = benchmarkRtf[tier]!;
    if (rtf < 0.3) return TierPerformance.fast;
    if (rtf < 0.8) return TierPerformance.moderate;
    return TierPerformance.slow;
  }

  // No benchmark data — estimate from VRAM and vendor heuristics.
  // Apple Silicon unified memory handles all tiers well.
  if (gpu.vendor == hw.GpuVendor.apple) {
    final vram = gpu.vramMB ?? 0;
    if (vram >= 8192) return TierPerformance.fast;
    if (vram >= 4096) return TierPerformance.moderate;
    return TierPerformance.slow;
  }

  // NVIDIA with CUDA — generally fast.
  if (gpu.vendor == hw.GpuVendor.nvidia && gpu.cudaAvailable) {
    final vram = gpu.vramMB ?? 0;
    if (tier == QualityTier.compact) return TierPerformance.fast;
    if (tier == QualityTier.balanced && vram >= 4096) {
      return TierPerformance.fast;
    }
    if (tier == QualityTier.premium && vram >= 6144) {
      return TierPerformance.moderate;
    }
    return TierPerformance.slow;
  }

  // Vulkan / integrated / CPU fallback — conservative estimate.
  if (tier == QualityTier.compact) return TierPerformance.moderate;
  return TierPerformance.slow;
}

/// Recommends the best tier based on benchmark RTF data.
/// Returns the fastest tier with RTF < 0.8, or premium if none qualify.
/// Returns null if no benchmark data available.
QualityTier? recommendTierFromBenchmark(Map<QualityTier, double> rtfMap) {
  if (rtfMap.isEmpty) return null;

  // Try tiers in order of quality, return first one that's fast enough.
  for (final tier in [
    QualityTier.compact,
    QualityTier.balanced,
    QualityTier.premium,
  ]) {
    final rtf = rtfMap[tier];
    if (rtf != null && rtf < 0.8) {
      return tier;
    }
  }

  // All tiers are slow - still recommend premium as best available.
  return QualityTier.premium;
}

/// Total download size for [tier]'s best model (human-readable).
String tierSizeLabel(QualityTier tier) {
  final model = bestModelForTier(tier);
  return model.sizeLabel;
}

// ---------------------------------------------------------------------------
// Download state
// ---------------------------------------------------------------------------

/// Status of a single download operation.
enum DownloadPhase { idle, downloading, extracting, verifying, done, error }

/// Progress state for the model download manager.
class ModelDownloadState {
  const ModelDownloadState({
    this.activeModelId,
    this.phase = DownloadPhase.idle,
    this.progressPercent = 0,
    this.bytesDownloaded = 0,
    this.totalBytes = 0,
    this.speedBytesPerSec = 0,
    this.etaSeconds,
    this.downloadStartedAt,
    this.statusLabel,
    this.errorMessage,
    this.downloadedModels = const {},
    this.serverReady = false,
  });

  /// Currently downloading model ID (null when idle).
  final String? activeModelId;
  final DownloadPhase phase;
  final int progressPercent;
  final int bytesDownloaded;
  final int totalBytes;

  /// Rolling average download speed in bytes/second.
  final double speedBytesPerSec;

  /// Estimated seconds remaining (null if unknown size or just started).
  final int? etaSeconds;

  /// When this download started (for elapsed time tracking).
  final DateTime? downloadStartedAt;

  /// Short status label for the current operation (e.g. "Downloading model…").
  final String? statusLabel;

  final String? errorMessage;

  /// Set of STT model IDs whose files exist on disk.
  final Set<String> downloadedModels;

  /// Whether whisper-server binary is present.
  final bool serverReady;

  bool get isDownloading => phase == DownloadPhase.downloading;
  bool get isError => phase == DownloadPhase.error;
  bool get isBusy =>
      phase == DownloadPhase.downloading ||
      phase == DownloadPhase.extracting ||
      phase == DownloadPhase.verifying;

  ModelDownloadState copyWith({
    String? activeModelId,
    DownloadPhase? phase,
    int? progressPercent,
    int? bytesDownloaded,
    int? totalBytes,
    double? speedBytesPerSec,
    int? etaSeconds,
    DateTime? downloadStartedAt,
    String? statusLabel,
    String? errorMessage,
    Set<String>? downloadedModels,
    bool? serverReady,
  }) {
    return ModelDownloadState(
      activeModelId: activeModelId ?? this.activeModelId,
      phase: phase ?? this.phase,
      progressPercent: progressPercent ?? this.progressPercent,
      bytesDownloaded: bytesDownloaded ?? this.bytesDownloaded,
      totalBytes: totalBytes ?? this.totalBytes,
      speedBytesPerSec: speedBytesPerSec ?? this.speedBytesPerSec,
      etaSeconds: etaSeconds ?? this.etaSeconds,
      downloadStartedAt: downloadStartedAt ?? this.downloadStartedAt,
      statusLabel: statusLabel ?? this.statusLabel,
      errorMessage: errorMessage,
      downloadedModels: downloadedModels ?? this.downloadedModels,
      serverReady: serverReady ?? this.serverReady,
    );
  }
}

// ---------------------------------------------------------------------------
// Disk scanner
// ---------------------------------------------------------------------------

/// Scans the STT directory and returns the current [ModelDownloadState].
///
/// Creates the directory if it does not exist (best-effort). Called during
/// notifier initialisation and on explicit [ModelDownloadNotifier.refresh].
ModelDownloadState _scanExistingModels() {
  final downloaded = <String>{};
  final dir = Directory(sttDir());
  if (!dir.existsSync()) {
    try {
      dir.createSync(recursive: true);
    } on FileSystemException {
      // Best-effort — will fail later with a clear error.
    }
  }
  if (dir.existsSync()) {
    for (final model in sttModels) {
      if (File(p.join(dir.path, model.filename)).existsSync()) {
        downloaded.add(model.id);
      }
    }
  }
  final serverExists = File(whisperServerPath()).existsSync();

  _log.info(
    'Scan: ${downloaded.length} STT models, server=${serverExists ? "ready" : "missing"}',
  );
  return ModelDownloadState(
    downloadedModels: downloaded,
    serverReady: serverExists,
  );
}

// ---------------------------------------------------------------------------
// Download notifier
// ---------------------------------------------------------------------------

class ModelDownloadNotifier extends Notifier<ModelDownloadState> {
  /// Injected fetcher — override in tests to avoid real network calls.
  @visibleForTesting
  HttpModelFetcher? fetcherOverride;

  /// Injected manifest loader — override in tests to feed a fixture
  /// manifest into the downloader without touching the network.
  @visibleForTesting
  WhisperServerManifestLoader? manifestLoaderOverride;

  /// Injected verifier — override in tests to avoid real file I/O.
  @visibleForTesting
  FileVerificationService? verifierOverride;

  /// Injected server downloader — override in tests.
  @visibleForTesting
  WhisperServerDownloader? serverDownloaderOverride;

  bool _autoDownloadAttempted = false;

  HttpModelFetcher get _fetcher => fetcherOverride ?? HttpModelFetcher();

  FileVerificationService get _verifier =>
      verifierOverride ?? const FileVerificationService();

  WhisperServerDownloader get _serverDownloader =>
      serverDownloaderOverride ??
      WhisperServerDownloader(
        fetcher: _fetcher,
        manifestLoader: manifestLoaderOverride,
      );

  @override
  ModelDownloadState build() {
    ref.onDispose(() {
      _fetcher.cancel('disposed');
    });
    // Scan disk for already-downloaded models.
    final initial = _scanExisting();

    // Self-heal: if models exist but server is missing, auto-download.
    if (!initial.serverReady &&
        initial.downloadedModels.isNotEmpty &&
        !_autoDownloadAttempted) {
      _autoDownloadAttempted = true;
      Future.microtask(() => ensureServerBinary());
    }

    return initial;
  }

  // -----------------------------------------------------------------------
  // Public API
  // -----------------------------------------------------------------------

  /// Downloads an STT model file. If whisper-server is missing, downloads
  /// that first. Orchestrates: Engine → Fetch → Verify → Activate.
  Future<void> downloadModel(String modelId) async {
    if (state.isBusy) return;

    final model = findSttModel(modelId);
    if (model == null) {
      state = state.copyWith(
        phase: DownloadPhase.error,
        errorMessage: 'Unknown model: $modelId',
      );
      return;
    }

    try {
      _ensureDir(sttDir());

      // Phase 1: Engine — ensure whisper-server binary exists.
      if (!state.serverReady) {
        _setEnginePhase(activeModelId: modelId);
        await _downloadServerBinary();
      }

      // Phase 2: Fetch — download model file.
      _log.info('Downloading model: ${model.id} (${model.sizeLabel})');
      _setModelFetchPhase(model, activeModelId: modelId);

      final destPath = p.join(sttDir(), model.filename);
      if (File(destPath).existsSync()) {
        _log.info('Model ${model.id} already exists, verifying…');
        state = state.copyWith(
          phase: DownloadPhase.verifying,
          statusLabel: 'verifying',
        );
        final result = await _verifier.verify(File(destPath), model.sha256);
        if (result is VerificationOk) {
          await _markModelDone(model.id);
          return;
        }
        await File(destPath).delete(); // Hash mismatch — re-download.
      }

      await _fetcher.fetch(
        url: model.url,
        destPath: destPath,
        expectedSize: model.sizeBytes,
        onProgress: (prog) => state = state.copyWith(
          progressPercent: prog.progressPercent,
          bytesDownloaded: prog.bytesReceived,
          totalBytes: prog.totalBytes,
          speedBytesPerSec: prog.speedBytesPerSec,
          etaSeconds: prog.etaSeconds,
        ),
      );

      // Phase 3: Verify — SHA256 check.
      state = state.copyWith(
        phase: DownloadPhase.verifying,
        progressPercent: 99,
        statusLabel: 'verifying',
      );
      final result = await _verifier.verify(File(destPath), model.sha256);
      if (result is! VerificationOk) {
        await File(destPath).delete().catchError((_) => File(destPath));
        state = state.copyWith(
          phase: DownloadPhase.error,
          errorMessage: 'SHA256 verification failed — file may be corrupt.',
        );
        return;
      }

      // Phase 4: Activate — persist model selection.
      await _markModelDone(model.id);
    } on DioException catch (e) {
      _handleDioError(e, logFn: _log.error);
    } on Exception catch (e) {
      _log.error('Download error: $e');
      state = state.copyWith(phase: DownloadPhase.error, errorMessage: '$e');
    }
  }

  /// Cancels the active download.
  void cancelDownload() {
    _fetcher.cancel('user cancelled');
    state = state.copyWith(
      phase: DownloadPhase.idle,
      activeModelId: null,
      progressPercent: 0,
    );
  }

  /// Ensures the whisper-server binary exists, downloading it if missing.
  ///
  /// Called automatically when the preflight check finds the server missing
  /// but at least one model is downloaded. Also safe to call manually.
  /// No-op if the server is already ready or a download is in progress.
  Future<void> ensureServerBinary() async {
    if (state.serverReady || state.isBusy) return;

    _log.info('Auto-downloading whisper-server (self-heal)');

    try {
      _ensureDir(sttDir());
      _setEnginePhase();
      await _downloadServerBinary();
      state = state.copyWith(phase: DownloadPhase.idle, progressPercent: 0);
      _log.info('Self-heal complete: whisper-server ready');
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        state = state.copyWith(phase: DownloadPhase.idle);
      } else {
        final msg = e.response?.statusCode == 403
            ? 'GitHub API rate limit reached.'
            : 'Download failed: ${e.message}';
        _log.warning('Self-heal failed: $msg');
        state = state.copyWith(phase: DownloadPhase.idle, errorMessage: msg);
      }
    } on Exception catch (e) {
      _log.warning('Self-heal failed: $e');
      state = state.copyWith(phase: DownloadPhase.idle, errorMessage: '$e');
    }
  }

  /// Deletes a downloaded model file.
  Future<void> deleteModel(String modelId) async {
    final model = findSttModel(modelId);
    if (model == null) return;

    final file = File(p.join(sttDir(), model.filename));
    if (file.existsSync()) {
      await file.delete();
    }
    state = state.copyWith(
      downloadedModels: {...state.downloadedModels}..remove(modelId),
    );
  }

  /// Refreshes disk scan.
  void refresh() {
    state = _scanExisting();
  }

  ModelDownloadState _scanExisting() => _scanExistingModels();

  /// Marks the server binary as incompatible and deletes it.
  ///
  /// Called by stt_service when a DLL-not-found crash is detected (wrong
  /// GPU binary variant). After this, `serverReady` is false and the
  /// self-heal logic will auto-download the correct binary.
  Future<void> invalidateServerBinary() async {
    try {
      await hw.deleteServerBinary(sttDir());
    } catch (e) {
      _log.warning('Failed to delete server binary: $e');
    }
    state = state.copyWith(serverReady: false);
    // Trigger self-heal for the correct GPU variant.
    Future.microtask(() => ensureServerBinary());
  }

  // -----------------------------------------------------------------------
  // Private — state helpers
  // -----------------------------------------------------------------------

  /// Creates/validates [dirPath] (best-effort).
  void _ensureDir(String dirPath) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
      _log.info('Created STT directory: $dirPath');
    }
  }

  /// Transitions to the engine-downloading phase.
  void _setEnginePhase({String? activeModelId}) {
    state = state.copyWith(
      activeModelId: activeModelId,
      phase: DownloadPhase.downloading,
      progressPercent: 0,
      downloadStartedAt: DateTime.now(),
      statusLabel: 'engine',
      speedBytesPerSec: 0,
      errorMessage: null,
    );
  }

  /// Transitions to the model-fetch phase.
  void _setModelFetchPhase(
    SttModelInfo model, {
    required String activeModelId,
  }) {
    state = state.copyWith(
      activeModelId: activeModelId,
      phase: DownloadPhase.downloading,
      progressPercent: 0,
      bytesDownloaded: 0,
      totalBytes: model.sizeBytes,
      downloadStartedAt: DateTime.now(),
      statusLabel: 'model',
      speedBytesPerSec: 0,
    );
  }

  /// Handles a [DioException] from a download, updating state accordingly.
  void _handleDioError(DioException e, {required void Function(String) logFn}) {
    if (e.type == DioExceptionType.cancel) {
      state = state.copyWith(phase: DownloadPhase.idle, activeModelId: null);
    } else {
      final msg = e.response?.statusCode == 403
          ? 'GitHub API rate limit reached. Please wait a few minutes.'
          : 'Download failed: ${e.message}';
      logFn(msg);
      state = state.copyWith(phase: DownloadPhase.error, errorMessage: msg);
    }
  }

  Future<void> _markModelDone(String modelId) async {
    state = state.copyWith(
      phase: DownloadPhase.done,
      activeModelId: modelId,
      progressPercent: 100,
      downloadedModels: {...state.downloadedModels, modelId},
      serverReady: true,
    );

    // Auto-activate the downloaded model so the STT service uses it.
    try {
      await ref
          .read(settingsProvider.notifier)
          .updateSettings((s) => s.copyWith(sttModel: modelId));
    } catch (e) {
      _log.warning('Failed to persist sttModel=$modelId: $e');
    }

    // After download completion the .tmp was already renamed to the final
    // file by HttpModelFetcher. Reap any OTHER orphaned .tmp fragments that
    // may still linger (fire-and-forget).
    unawaited(sweepOrphanedTmpFiles(directory: sttDir()));
  }

  // -----------------------------------------------------------------------
  // Private — server binary orchestration
  // -----------------------------------------------------------------------

  /// Downloads the whisper-server binary via [WhisperServerDownloader],
  /// forwarding progress/phase updates to [state].
  Future<void> _downloadServerBinary() async {
    final settings = ref.read(settingsProvider).value ?? AppSettings.defaults;
    await _serverDownloader.download(
      destDir: sttDir(),
      gpuMode: settings.gpuAcceleration,
      onProgress: (prog) => state = state.copyWith(
        progressPercent: prog.progressPercent,
        bytesDownloaded: prog.bytesReceived,
        totalBytes: prog.totalBytes,
        speedBytesPerSec: prog.speedBytesPerSec,
        etaSeconds: prog.etaSeconds,
      ),
      onExtracting: () =>
          state = state.copyWith(phase: DownloadPhase.extracting),
    );
    state = state.copyWith(serverReady: true);
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final modelDownloadProvider =
    NotifierProvider<ModelDownloadNotifier, ModelDownloadState>(
      ModelDownloadNotifier.new,
    );
