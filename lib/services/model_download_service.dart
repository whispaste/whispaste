/// Model download service — manages downloading STT/LLM models and server
/// binaries from HuggingFace and GitHub with progress, SHA256 verification,
/// and resume support.
library;

import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../core/config/settings_provider.dart';
import '../core/app_info.dart';
import '../core/logging/app_logger.dart';
import 'hardware_info_service.dart' as hw;
import 'path_service.dart';

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
    this.description = '',
  });

  final String id;
  final String label;
  final String filename;
  final int sizeBytes;
  final String url;
  final String sha256;
  final String description;

  String get sizeLabel {
    if (sizeBytes >= 1024 * 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    return '${(sizeBytes / (1024 * 1024)).round()} MB';
  }
}

/// All available STT models (quantized, from HuggingFace whisper.cpp).
const List<SttModelInfo> sttModels = [
  SttModelInfo(
    id: 'whisper-tiny',
    label: 'Tiny',
    filename: 'ggml-tiny-q5_1.bin',
    sizeBytes: 32152673,
    url:
        'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny-q5_1.bin',
    sha256: '818710568da3ca15689e31a743197b520007872ff9576237bda97bd1b469c3d7',
    description: 'Fastest, lower accuracy',
  ),
  SttModelInfo(
    id: 'whisper-base',
    label: 'Base',
    filename: 'ggml-base-q5_1.bin',
    sizeBytes: 59700000,
    url:
        'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base-q5_1.bin',
    sha256: '422f1ae452ade6f30a004d7e5c6a43195e4433bc370bf23fac9cc591f01a8898',
    description: 'Good balance of speed and accuracy',
  ),
  SttModelInfo(
    id: 'whisper-small',
    label: 'Small',
    filename: 'ggml-small-q5_1.bin',
    sizeBytes: 190085487,
    url:
        'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small-q5_1.bin',
    sha256: 'ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb',
    description: 'Recommended for most users',
  ),
  SttModelInfo(
    id: 'whisper-medium',
    label: 'Medium',
    filename: 'ggml-medium-q5_0.bin',
    sizeBytes: 539212467,
    url:
        'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium-q5_0.bin',
    sha256: '19fea4b380c3a618ec4723c3eef2eb785ffba0d0538cf43f8f235e7b3b34220f',
    description: 'High accuracy, needs more RAM',
  ),
  SttModelInfo(
    id: 'whisper-large-v3-turbo',
    label: 'Large v3 Turbo',
    filename: 'ggml-large-v3-turbo-q5_0.bin',
    sizeBytes: 574041195,
    url:
        'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin',
    sha256: '394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2',
    description: 'Best speed/quality ratio for large models',
  ),
  SttModelInfo(
    id: 'whisper-large-v3',
    label: 'Large v3',
    filename: 'ggml-large-v3-q5_0.bin',
    sizeBytes: 1081140203,
    url:
        'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-q5_0.bin',
    sha256: 'd75795ecff3f83b5faa89d1900604ad8c780abd5739fae406de19f23ecd98ad1',
    description: 'Maximum accuracy, requires GPU',
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
// LLM Model registry
// ---------------------------------------------------------------------------

/// Metadata for a downloadable LLM model.
class LlmModelInfo {
  const LlmModelInfo({
    required this.id,
    required this.label,
    required this.filename,
    required this.sizeBytes,
    required this.url,
    this.sha256,
    this.description = '',
  });

  final String id;
  final String label;
  final String filename;
  final int sizeBytes;
  final String url;

  /// SHA256 hash. Null means skip verification (e.g. for frequently-requantized
  /// community models where the hash changes per rebuild).
  final String? sha256;
  final String description;

  String get sizeLabel {
    if (sizeBytes >= 1024 * 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    return '${(sizeBytes / (1024 * 1024)).round()} MB';
  }
}

/// All available LLM models.
///
/// Currently only Qwen3-1.7B Q4_K_M — the optimal local model for
/// short-form post-processing (119 languages, MMLU 66.9%, Apache 2.0).
const List<LlmModelInfo> llmModels = [
  LlmModelInfo(
    id: 'qwen3-1.7b',
    label: 'Qwen3 1.7B',
    filename: 'Qwen_Qwen3-1.7B-Q4_K_M.gguf',
    sizeBytes: 1283000000, // ~1.28 GB
    url:
        'https://huggingface.co/bartowski/Qwen_Qwen3-1.7B-GGUF/resolve/main/Qwen_Qwen3-1.7B-Q4_K_M.gguf',
    description: 'Fast local post-processing (1.3 GB, 119 languages)',
  ),
];

/// Looks up an LLM model by ID. Returns null if not found.
LlmModelInfo? findLlmModel(String id) {
  for (final m in llmModels) {
    if (m.id == id) return m;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Quality Tiers — user-facing abstraction over raw model names
// ---------------------------------------------------------------------------

/// User-facing quality tiers that abstract away model internals.
enum QualityTier { compact, balanced, premium }

/// Safety/availability level of a quality tier for a given GPU.
/// Used to determine UI display (warning vs disabled) and behavior.
enum TierSafety {
  /// Tier can run reliably on this GPU.
  usable,

  /// Tier is usable but will be slow (no GPU acceleration).
  slowWithoutGpu,

  /// Tier may crash or run poorly due to GPU memory limits.
  /// User CAN still select it — this is a warning, not a blocker.
  vramRisky,

  /// Tier is extremely unlikely to work (integrated GPU + large model).
  /// User CAN still select it with explicit confirmation.
  vramCritical,
}

/// Returns the ordered list of models belonging to [tier] (best first).
///
/// Order is explicit — the first entry in each tier is the recommended
/// default returned by [bestModelForTier].
List<SttModelInfo> modelsForTier(QualityTier tier) {
  final ids = switch (tier) {
    QualityTier.compact => ['whisper-small', 'whisper-base', 'whisper-tiny'],
    QualityTier.balanced => ['whisper-medium'],
    QualityTier.premium => ['whisper-large-v3-turbo', 'whisper-large-v3'],
  };
  return ids.map((id) => sttModels.firstWhere((m) => m.id == id)).toList();
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

/// Returns the safety level of [tier] for [gpu].
/// This is informational — users can still select any tier.
TierSafety tierSafety(QualityTier tier, hw.GpuInfo gpu) {
  final vram = gpu.vramMB ?? 0;

  // Compact tier always usable.
  if (tier == QualityTier.compact) return TierSafety.usable;

  // CPU-only: usable but slow.
  if (!gpu.hasGpu) return TierSafety.slowWithoutGpu;

  // Apple Silicon — generous thresholds.
  if (gpu.vendor == hw.GpuVendor.apple) {
    if (tier == QualityTier.premium) {
      return vram >= 4096 ? TierSafety.usable : TierSafety.vramRisky;
    }
    return TierSafety.usable;
  }

  // NVIDIA dedicated GPU.
  if (gpu.vendor == hw.GpuVendor.nvidia) {
    final usableVram = (vram * 0.70).round();
    final premiumNeeded = hw.sttModelVramMB['whisper-large-v3-turbo'] ?? 2600;
    final balancedNeeded = hw.sttModelVramMB['whisper-medium'] ?? 1500;

    if (tier == QualityTier.premium) {
      if (premiumNeeded <= usableVram) return TierSafety.usable;
      return TierSafety.vramRisky;
    }
    if (tier == QualityTier.balanced) {
      if (balancedNeeded <= usableVram) return TierSafety.usable;
      return TierSafety.vramRisky;
    }
  }

  // Intel/AMD integrated — very conservative.
  if (gpu.vendor == hw.GpuVendor.intel || gpu.vendor == hw.GpuVendor.amd) {
    if (tier == QualityTier.premium) return TierSafety.vramCritical;
    if (tier == QualityTier.balanced) {
      return vram >= 4096 ? TierSafety.vramRisky : TierSafety.vramCritical;
    }
  }

  return TierSafety.usable;
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
    this.downloadedLlmModels = const {},
    this.llmServerReady = false,
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

  /// Set of LLM model IDs whose files exist on disk.
  final Set<String> downloadedLlmModels;

  /// Whether llama-server binary is present.
  final bool llmServerReady;

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
    Set<String>? downloadedLlmModels,
    bool? llmServerReady,
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
      downloadedLlmModels: downloadedLlmModels ?? this.downloadedLlmModels,
      llmServerReady: llmServerReady ?? this.llmServerReady,
    );
  }
}

// ---------------------------------------------------------------------------
// Download notifier
// ---------------------------------------------------------------------------

class ModelDownloadNotifier extends Notifier<ModelDownloadState> {
  CancelToken? _cancelToken;
  bool _autoDownloadAttempted = false;
  final _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 10),
      headers: {'User-Agent': appUserAgent},
    ),
  );

  @override
  ModelDownloadState build() {
    ref.onDispose(() {
      _cancelToken?.cancel('disposed');
      // Dio instance is kept alive so it can be reused for retry/download
      // attempts after the notifier is re-initialized (e.g., after app reset).
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
  /// that first.
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

    _cancelToken = CancelToken();

    try {
      // Ensure target directory exists before any I/O.
      final dir = Directory(sttDir());
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
        _log.info('Created STT directory: ${dir.path}');
      }

      // Phase 1: Ensure whisper-server binary exists.
      if (!state.serverReady) {
        state = state.copyWith(
          activeModelId: modelId,
          phase: DownloadPhase.downloading,
          progressPercent: 0,
          downloadStartedAt: DateTime.now(),
          statusLabel: 'engine',
          speedBytesPerSec: 0,
          errorMessage: null,
        );
        await _downloadWhisperServer();
      }

      // Phase 2: Download model file.
      _log.info('Downloading model: ${model.id} (${model.sizeLabel})');
      state = state.copyWith(
        activeModelId: modelId,
        phase: DownloadPhase.downloading,
        progressPercent: 0,
        bytesDownloaded: 0,
        totalBytes: model.sizeBytes,
        downloadStartedAt: DateTime.now(),
        statusLabel: 'model',
        speedBytesPerSec: 0,
      );

      final destPath = p.join(sttDir(), model.filename);
      if (File(destPath).existsSync()) {
        _log.info('Model ${model.id} already exists, verifying…');
        state = state.copyWith(
          phase: DownloadPhase.verifying,
          statusLabel: 'verifying',
        );
        final ok = await _verifySha256(destPath, model.sha256);
        if (ok) {
          await _markModelDone(model.id);
          return;
        }
        // Hash mismatch — re-download.
        await File(destPath).delete();
      }

      await _downloadFile(
        url: model.url,
        destPath: destPath,
        expectedSize: model.sizeBytes,
      );

      // Phase 3: Verify SHA256.
      state = state.copyWith(
        phase: DownloadPhase.verifying,
        progressPercent: 99,
        statusLabel: 'verifying',
      );
      final ok = await _verifySha256(destPath, model.sha256);
      if (!ok) {
        await File(destPath).delete().catchError((_) => File(destPath));
        state = state.copyWith(
          phase: DownloadPhase.error,
          errorMessage: 'SHA256 verification failed — file may be corrupt.',
        );
        return;
      }

      await _markModelDone(model.id);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        state = state.copyWith(phase: DownloadPhase.idle, activeModelId: null);
      } else {
        final msg = e.response?.statusCode == 403
            ? 'GitHub API rate limit reached. Please wait a few minutes.'
            : 'Download failed: ${e.message}';
        _log.error(msg);
        state = state.copyWith(phase: DownloadPhase.error, errorMessage: msg);
      }
    } on Exception catch (e) {
      _log.error('Download error: $e');
      state = state.copyWith(phase: DownloadPhase.error, errorMessage: '$e');
    }
  }

  /// Cancels the active download.
  void cancelDownload() {
    _cancelToken?.cancel('user cancelled');
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

    _cancelToken = CancelToken();
    _log.info('Auto-downloading whisper-server (self-heal)');

    try {
      final dir = Directory(sttDir());
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }

      state = state.copyWith(
        phase: DownloadPhase.downloading,
        progressPercent: 0,
        downloadStartedAt: DateTime.now(),
        statusLabel: 'engine',
        speedBytesPerSec: 0,
        errorMessage: null,
      );

      await _downloadWhisperServer();

      // Reset to idle (not done — no model was downloaded).
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

  // -----------------------------------------------------------------------
  // LLM — Public API
  // -----------------------------------------------------------------------

  /// Downloads an LLM model file. If llama-server is missing, downloads
  /// that first.
  Future<void> downloadLlmModel(String modelId) async {
    if (state.isBusy) return;

    final model = findLlmModel(modelId);
    if (model == null) {
      state = state.copyWith(
        phase: DownloadPhase.error,
        errorMessage: 'Unknown LLM model: $modelId',
      );
      return;
    }

    _cancelToken = CancelToken();

    try {
      final dir = Directory(llmDir());
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
        _log.info('Created LLM directory: ${dir.path}');
      }

      // Phase 1: Ensure llama-server binary exists.
      if (!state.llmServerReady) {
        state = state.copyWith(
          activeModelId: modelId,
          phase: DownloadPhase.downloading,
          progressPercent: 0,
          downloadStartedAt: DateTime.now(),
          statusLabel: 'llm-engine',
          speedBytesPerSec: 0,
          errorMessage: null,
        );
        await _downloadLlamaServer();
      }

      // Phase 2: Download model file.
      _log.info('Downloading LLM model: ${model.id} (${model.sizeLabel})');
      state = state.copyWith(
        activeModelId: modelId,
        phase: DownloadPhase.downloading,
        progressPercent: 0,
        bytesDownloaded: 0,
        totalBytes: model.sizeBytes,
        downloadStartedAt: DateTime.now(),
        statusLabel: 'llm-model',
        speedBytesPerSec: 0,
      );

      final destPath = p.join(llmDir(), model.filename);
      if (File(destPath).existsSync()) {
        _log.info('LLM model ${model.id} already exists, verifying…');
        if (model.sha256 != null) {
          state = state.copyWith(
            phase: DownloadPhase.verifying,
            statusLabel: 'verifying',
          );
          final ok = await _verifySha256(destPath, model.sha256!);
          if (ok) {
            await _markLlmModelDone(model.id);
            return;
          }
          await File(destPath).delete();
        } else {
          // No SHA256 — trust existing file.
          await _markLlmModelDone(model.id);
          return;
        }
      }

      await _downloadFile(
        url: model.url,
        destPath: destPath,
        expectedSize: model.sizeBytes,
      );

      // Phase 3: Verify SHA256 if available.
      if (model.sha256 != null) {
        state = state.copyWith(
          phase: DownloadPhase.verifying,
          progressPercent: 99,
          statusLabel: 'verifying',
        );
        final ok = await _verifySha256(destPath, model.sha256!);
        if (!ok) {
          await File(destPath).delete().catchError((_) => File(destPath));
          state = state.copyWith(
            phase: DownloadPhase.error,
            errorMessage: 'SHA256 verification failed — file may be corrupt.',
          );
          return;
        }
      }

      await _markLlmModelDone(model.id);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        state = state.copyWith(phase: DownloadPhase.idle, activeModelId: null);
      } else {
        final msg = e.response?.statusCode == 403
            ? 'GitHub API rate limit reached. Please wait a few minutes.'
            : 'Download failed: ${e.message}';
        _log.error(msg);
        state = state.copyWith(phase: DownloadPhase.error, errorMessage: msg);
      }
    } on Exception catch (e) {
      _log.error('LLM download error: $e');
      state = state.copyWith(phase: DownloadPhase.error, errorMessage: '$e');
    }
  }

  /// Ensures the llama-server binary exists, downloading it if missing.
  Future<void> ensureLlamaServerBinary() async {
    if (state.llmServerReady || state.isBusy) return;

    _cancelToken = CancelToken();
    _log.info('Downloading llama-server binary');

    try {
      final dir = Directory(llmDir());
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }

      state = state.copyWith(
        phase: DownloadPhase.downloading,
        progressPercent: 0,
        downloadStartedAt: DateTime.now(),
        statusLabel: 'llm-engine',
        speedBytesPerSec: 0,
        errorMessage: null,
      );

      await _downloadLlamaServer();

      state = state.copyWith(phase: DownloadPhase.idle, progressPercent: 0);
      _log.info('llama-server download complete');
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        state = state.copyWith(phase: DownloadPhase.idle);
      } else {
        final msg = e.response?.statusCode == 403
            ? 'GitHub API rate limit reached.'
            : 'Download failed: ${e.message}';
        _log.warning('llama-server download failed: $msg');
        state = state.copyWith(phase: DownloadPhase.idle, errorMessage: msg);
      }
    } on Exception catch (e) {
      _log.warning('llama-server download failed: $e');
      state = state.copyWith(phase: DownloadPhase.idle, errorMessage: '$e');
    }
  }

  /// Deletes a downloaded LLM model file.
  Future<void> deleteLlmModel(String modelId) async {
    final model = findLlmModel(modelId);
    if (model == null) return;

    final file = File(p.join(llmDir(), model.filename));
    if (file.existsSync()) {
      await file.delete();
    }
    state = state.copyWith(
      downloadedLlmModels: {...state.downloadedLlmModels}..remove(modelId),
    );
  }

  /// Marks the llama-server binary as incompatible and deletes it.
  Future<void> invalidateLlamaServerBinary() async {
    try {
      final dir = Directory(llmDir());
      if (dir.existsSync()) {
        for (final f in dir.listSync()) {
          if (f is File) {
            final name = p.basename(f.path).toLowerCase();
            if (name.startsWith('llama-server') || name.endsWith('.dll')) {
              await f.delete();
            }
          }
        }
      }
    } catch (e) {
      _log.warning('Failed to delete llama-server binary: $e');
    }
    state = state.copyWith(llmServerReady: false);
  }

  ModelDownloadState _scanExisting() {
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

    // Scan LLM models + binary.
    final downloadedLlm = <String>{};
    final llmDirectory = Directory(llmDir());
    if (!llmDirectory.existsSync()) {
      try {
        llmDirectory.createSync(recursive: true);
      } on FileSystemException {
        // Best-effort.
      }
    }
    if (llmDirectory.existsSync()) {
      for (final model in llmModels) {
        if (File(p.join(llmDirectory.path, model.filename)).existsSync()) {
          downloadedLlm.add(model.id);
        }
      }
    }
    final llmServerExists = File(llamaServerPath()).existsSync();

    _log.info(
      'Scan: ${downloaded.length} STT models, server=${serverExists ? "ready" : "missing"}, '
      '${downloadedLlm.length} LLM models, llama=${llmServerExists ? "ready" : "missing"}',
    );
    return ModelDownloadState(
      downloadedModels: downloaded,
      serverReady: serverExists,
      downloadedLlmModels: downloadedLlm,
      llmServerReady: llmServerExists,
    );
  }

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
  }

  // -----------------------------------------------------------------------
  // Private — file download with progress
  // -----------------------------------------------------------------------

  Future<void> _downloadFile({
    required String url,
    required String destPath,
    required int expectedSize,
  }) async {
    final tmpPath = '$destPath.tmp';
    int startByte = 0;
    final tmpFile = File(tmpPath);

    // Resume partial download.
    if (tmpFile.existsSync()) {
      startByte = tmpFile.lengthSync();
      _log.info('Resuming download from byte $startByte');
    }

    final response = await _dio.get<ResponseBody>(
      url,
      cancelToken: _cancelToken,
      options: Options(
        responseType: ResponseType.stream,
        headers: startByte > 0 ? {'Range': 'bytes=$startByte-'} : null,
      ),
    );

    final totalBytes = _resolveTotal(response, startByte, expectedSize);

    final sink = tmpFile.openWrite(
      mode: startByte > 0 ? FileMode.append : FileMode.write,
    );
    int received = startByte;

    // Rolling speed tracker — sample every ~500ms for a smooth 5s window.
    final speedSamples = <_SpeedSample>[];
    var lastSpeedUpdate = DateTime.now();

    try {
      await for (final chunk in response.data!.stream) {
        sink.add(chunk);
        received += chunk.length;

        final now = DateTime.now();
        final sinceLastUpdate = now.difference(lastSpeedUpdate);

        // Update speed/ETA at most every 500ms to avoid excessive rebuilds.
        double speed = state.speedBytesPerSec;
        int? eta = state.etaSeconds;
        if (sinceLastUpdate.inMilliseconds >= 500) {
          lastSpeedUpdate = now;
          speedSamples.add(_SpeedSample(now, received));
          // Keep only last 5 seconds of samples.
          final cutoff = now.subtract(const Duration(seconds: 5));
          speedSamples.removeWhere((s) => s.time.isBefore(cutoff));

          if (speedSamples.length >= 2) {
            final first = speedSamples.first;
            final elapsed = now.difference(first.time).inMilliseconds;
            if (elapsed > 0) {
              speed = (received - first.bytes) * 1000 / elapsed;
              final remaining = totalBytes > 0 ? totalBytes - received : 0;
              eta = speed > 0 ? (remaining / speed).ceil() : null;
            }
          }
        }

        final pct = totalBytes > 0 ? (received * 100 ~/ totalBytes) : 0;
        state = state.copyWith(
          progressPercent: pct.clamp(0, 99),
          bytesDownloaded: received,
          totalBytes: totalBytes,
          speedBytesPerSec: speed,
          etaSeconds: totalBytes > 0 ? eta : null,
        );
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    // Atomic rename.
    if (File(destPath).existsSync()) {
      await File(destPath).delete();
    }
    await tmpFile.rename(destPath);
  }

  int _resolveTotal(Response<ResponseBody> resp, int start, int expected) {
    final cl = resp.headers['content-length'];
    if (cl != null && cl.isNotEmpty) {
      final parsed = int.tryParse(cl.first);
      if (parsed != null) return start + parsed;
    }
    return expected;
  }

  // -----------------------------------------------------------------------
  // Private — SHA256 verification
  // -----------------------------------------------------------------------

  Future<bool> _verifySha256(String filePath, String expectedHash) async {
    _log.info('Verifying SHA256 of ${p.basename(filePath)}');
    final file = File(filePath);
    if (!file.existsSync()) return false;

    final digest = await sha256.bind(file.openRead()).first;
    final actualHash = digest.toString();
    final ok = actualHash == expectedHash;
    if (!ok) {
      _log.warning(
        'SHA256 mismatch: expected=$expectedHash actual=$actualHash',
      );
    }
    return ok;
  }

  // -----------------------------------------------------------------------
  // Private — whisper-server binary download
  // -----------------------------------------------------------------------

  Future<void> _downloadWhisperServer() async {
    final gpu = await hw.detectGpu();
    _log.info(
      'Downloading whisper-server binary '
      '(gpu=${gpu.vendor.name}, name="${gpu.name}", '
      'vram=${gpu.vramMB ?? "?"}MB, cuda=${gpu.cudaAvailable}, '
      'vulkan=${gpu.vulkanAvailable})',
    );

    final settings = ref.read(settingsProvider).value ?? AppSettings.defaults;
    final gpuMode = settings.gpuAcceleration;

    // Source priority: WhisPaste-owned releases (may have Vulkan/custom
    // builds), then upstream whisper.cpp (has CUDA + CPU/BLAS).
    const repos = [('whispaste', 'whispaste'), ('ggml-org', 'whisper.cpp')];

    String? lastError;

    for (final (owner, repo) in repos) {
      // Retry each repo up to 2 times for transient failures.
      for (var attempt = 1; attempt <= 2; attempt++) {
        try {
          final assetUrl = await _findServerAsset(
            owner: owner,
            repo: repo,
            gpuMode: gpuMode,
            isWhisPaste: owner == 'whispaste',
          );
          if (assetUrl == null) break; // No matching asset, try next repo.

          _log.info(
            'Downloading from $owner/$repo (attempt $attempt): '
            '${Uri.parse(assetUrl).pathSegments.last}',
          );

          // Size varies: CPU/BLAS ~17 MB, Vulkan ~30 MB, CUDA 12 ~460 MB.
          final isCuda =
              assetUrl.contains('cuda') || assetUrl.contains('cublas');
          final estimatedSize = isCuda ? 460 * 1024 * 1024 : 30 * 1024 * 1024;
          final zipPath = p.join(sttDir(), '_whisper-server.zip');
          await _downloadFile(
            url: assetUrl,
            destPath: zipPath,
            expectedSize: estimatedSize,
          );

          state = state.copyWith(phase: DownloadPhase.extracting);

          await _extractServerZip(zipPath, sttDir());
          await File(zipPath).delete().catchError((_) => File(zipPath));

          // Write metadata so startup validation can verify compatibility
          // without relying on DLL heuristics alone.
          final assetName = Uri.parse(assetUrl).pathSegments.lastOrNull ?? '';
          await hw.writeServerBinaryInfo(
            sttDir(),
            gpu,
            sourceRepo: '$owner/$repo',
            assetName: assetName,
          );

          state = state.copyWith(serverReady: true);
          _log.info('whisper-server ready (source=$owner/$repo)');
          return;
        } on DioException catch (e) {
          final status = e.response?.statusCode;
          lastError = status == 403
              ? 'GitHub API rate limit exceeded (HTTP 403)'
              : 'Network error: ${e.message} (HTTP $status)';
          _log.warning(
            'Server download failed from $owner/$repo '
            '(attempt $attempt): $lastError',
          );
          if (e.type == DioExceptionType.cancel) rethrow;
          if (status == 403) break; // Rate limited — skip to next repo.
          if (attempt < 2) {
            await Future<void>.delayed(Duration(seconds: 2 * attempt));
          }
        } on Exception catch (e) {
          lastError = '$e';
          _log.warning(
            'Server download failed from $owner/$repo '
            '(attempt $attempt): $e',
          );
          if (attempt < 2) {
            await Future<void>.delayed(Duration(seconds: 2 * attempt));
          }
        }
      }
    }

    _log.error('Could not download whisper-server from any source');
    throw Exception(lastError ?? 'Could not download whisper-server.');
  }

  /// Queries GitHub releases API and finds the best matching asset.
  ///
  /// For the WhisPaste repo, queries releases and finds the most recent one
  /// tagged `whisper-server-*` (built by `build-whisper-server.yml`). Each
  /// whisper.cpp version gets its own immutable release tag, e.g.
  /// `whisper-server-v1.8.4`. For upstream repos, queries the latest release.
  Future<String?> _findServerAsset({
    required String owner,
    required String repo,
    required String gpuMode,
    required bool isWhisPaste,
  }) async {
    Map<String, dynamic>? releaseData;

    if (isWhisPaste) {
      // WhisPaste uses versioned tags (whisper-server-v*). Query the
      // releases list and pick the first one with the right prefix.
      releaseData = await _findWhisPasteServerRelease(owner, repo);
      if (releaseData == null) return null;
    } else {
      // Upstream: just query the latest release.
      final apiUrl =
          'https://api.github.com/repos/$owner/$repo/releases/latest';
      final Response<Map<String, dynamic>> response;
      try {
        response = await _dio.get<Map<String, dynamic>>(
          apiUrl,
          cancelToken: _cancelToken,
          options: Options(
            headers: {'Accept': 'application/vnd.github.v3+json'},
          ),
        );
      } on DioException catch (e) {
        if (e.response?.statusCode == 404) {
          _log.info('No releases in $owner/$repo');
          return null;
        }
        rethrow;
      }
      releaseData = response.data;
    }

    // Check GitHub rate limit from response headers (upstream path only;
    // WhisPaste path handles this in _findWhisPasteServerRelease).

    final assets = (releaseData?['assets'] as List<dynamic>?) ?? [];
    if (assets.isEmpty) {
      _log.info('No assets in $owner/$repo release');
      return null;
    }

    // Build priority list of asset name patterns based on detected GPU.
    final patterns = await _serverAssetPatterns(gpuMode, isWhisPaste);

    // Architecture filter: match platform to expected binary arch.
    final archPattern = Platform.isMacOS ? 'arm64' : 'x64';

    for (final pattern in patterns) {
      for (final asset in assets) {
        final assetMap = asset as Map<String, dynamic>;
        final name = (assetMap['name'] as String?) ?? '';
        final lowerName = name.toLowerCase();
        if (lowerName.contains(pattern) && lowerName.contains(archPattern)) {
          _log.info(
            'Selected server asset: $name (pattern=$pattern, '
            'arch=$archPattern, repo=$owner/$repo)',
          );
          return assetMap['browser_download_url'] as String?;
        }
      }
    }

    _log.info(
      'No matching server asset in $owner/$repo '
      '(patterns=$patterns, arch=$archPattern, '
      'available=${assets.map((a) => (a as Map)['name']).toList()})',
    );
    return null;
  }

  /// Finds the most recent WhisPaste whisper-server release (tag prefix
  /// `whisper-server-`). Returns the release JSON map or `null`.
  Future<Map<String, dynamic>?> _findWhisPasteServerRelease(
    String owner,
    String repo,
  ) async {
    final apiUrl =
        'https://api.github.com/repos/$owner/$repo/releases?per_page=20';
    try {
      final response = await _dio.get<List<dynamic>>(
        apiUrl,
        cancelToken: _cancelToken,
        options: Options(headers: {'Accept': 'application/vnd.github.v3+json'}),
      );

      final remaining = response.headers['x-ratelimit-remaining']?.firstOrNull;
      if (remaining != null) {
        final rem = int.tryParse(remaining) ?? -1;
        if (rem <= 5) {
          _log.warning('GitHub API rate limit low: $rem remaining');
        }
      }

      final releases = response.data ?? [];
      for (final release in releases) {
        final r = release as Map<String, dynamic>;
        final tag = (r['tag_name'] as String?) ?? '';
        if (tag.startsWith('whisper-server-')) {
          _log.info('Found WhisPaste server release: $tag');
          return r;
        }
      }

      _log.info('No whisper-server-* release found in $owner/$repo');
      return null;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        _log.info('No releases endpoint for $owner/$repo');
        return null;
      }
      rethrow;
    }
  }

  Future<List<String>> _serverAssetPatterns(
    String gpuMode,
    bool isWhisPaste,
  ) async {
    final gpu = await hw.detectGpu();
    return hw.serverAssetPatterns(gpu, gpuMode, isWhisPaste);
  }

  /// Extracts whisper-server.exe and DLLs from a ZIP archive.
  Future<void> _extractServerZip(String zipPath, String destDir) async {
    final bytes = await File(zipPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    // Clean old server files.
    final destDirObj = Directory(destDir);
    if (destDirObj.existsSync()) {
      for (final f in destDirObj.listSync()) {
        if (f is File) {
          final name = p.basename(f.path).toLowerCase();
          if (name == 'whisper-server.exe' || name.endsWith('.dll')) {
            await f.delete();
          }
        }
      }
    }

    for (final file in archive) {
      if (file.isFile) {
        final name = p.basename(file.name).toLowerCase();
        if (name.endsWith('.exe') || name.endsWith('.dll')) {
          // Zip Slip protection.
          final outPath = p.join(destDir, p.basename(file.name));
          if (!p.isWithin(destDir, outPath)) continue;

          // Rename server.exe → whisper-server.exe if needed.
          String finalName = p.basename(file.name);
          if (finalName.toLowerCase() == 'server.exe') {
            finalName = 'whisper-server.exe';
          }
          final finalPath = p.join(destDir, finalName);
          final outFile = File(finalPath);
          await outFile.writeAsBytes(file.content as List<int>);
        }
      }
    }

    // Verify extraction produced the expected binary.
    if (!File(p.join(destDir, 'whisper-server.exe')).existsSync()) {
      throw Exception('whisper-server.exe not found in archive');
    }
  }

  // -----------------------------------------------------------------------
  // Private — llama-server binary download
  // -----------------------------------------------------------------------

  Future<void> _downloadLlamaServer() async {
    final gpu = await hw.detectGpu();
    _log.info(
      'Downloading llama-server binary '
      '(gpu=${gpu.vendor.name}, cuda=${gpu.cudaAvailable}, '
      'vulkan=${gpu.vulkanAvailable})',
    );

    final settings = ref.read(settingsProvider).value ?? AppSettings.defaults;
    final gpuMode = settings.gpuAcceleration;

    // Only upstream source — llama.cpp releases.
    const owner = 'ggml-org';
    const repo = 'llama.cpp';

    for (var attempt = 1; attempt <= 2; attempt++) {
      try {
        final assetUrl = await _findServerAsset(
          owner: owner,
          repo: repo,
          gpuMode: gpuMode,
          isWhisPaste: false,
        );
        if (assetUrl == null) break;

        _log.info(
          'Downloading llama-server from $owner/$repo (attempt $attempt): '
          '${Uri.parse(assetUrl).pathSegments.last}',
        );

        final isCuda = assetUrl.contains('cuda') || assetUrl.contains('cublas');
        final estimatedSize = isCuda ? 500 * 1024 * 1024 : 40 * 1024 * 1024;
        final zipPath = p.join(llmDir(), '_llama-server.zip');
        await _downloadFile(
          url: assetUrl,
          destPath: zipPath,
          expectedSize: estimatedSize,
        );

        state = state.copyWith(phase: DownloadPhase.extracting);

        await _extractLlamaServerZip(zipPath, llmDir());
        await File(zipPath).delete().catchError((_) => File(zipPath));

        state = state.copyWith(llmServerReady: true);
        _log.info('llama-server ready');
        return;
      } on DioException catch (e) {
        final status = e.response?.statusCode;
        _log.warning(
          'llama-server download failed (attempt $attempt): '
          '${e.message} (HTTP $status)',
        );
        if (e.type == DioExceptionType.cancel) rethrow;
        if (status == 403) break;
        if (attempt < 2) {
          await Future<void>.delayed(Duration(seconds: 2 * attempt));
        }
      } on Exception catch (e) {
        _log.warning('llama-server download failed (attempt $attempt): $e');
        if (attempt < 2) {
          await Future<void>.delayed(Duration(seconds: 2 * attempt));
        }
      }
    }

    _log.error('Could not download llama-server');
    throw Exception('Could not download llama-server.');
  }

  /// Extracts llama-server binary and DLLs from a ZIP archive.
  Future<void> _extractLlamaServerZip(String zipPath, String destDir) async {
    final bytes = await File(zipPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    // Clean old llama-server files.
    final destDirObj = Directory(destDir);
    if (destDirObj.existsSync()) {
      for (final f in destDirObj.listSync()) {
        if (f is File) {
          final name = p.basename(f.path).toLowerCase();
          if (name.startsWith('llama-server') || name.endsWith('.dll')) {
            await f.delete();
          }
        }
      }
    }

    final serverExeName = Platform.isWindows
        ? 'llama-server.exe'
        : 'llama-server';

    for (final file in archive) {
      if (file.isFile) {
        final name = p.basename(file.name).toLowerCase();
        if (name.endsWith('.exe') ||
            name.endsWith('.dll') ||
            name.endsWith('.so') ||
            name.endsWith('.dylib') ||
            name == 'llama-server') {
          final outPath = p.join(destDir, p.basename(file.name));
          if (!p.isWithin(destDir, outPath)) continue;

          // Rename to llama-server if the archive uses a different name.
          String finalName = p.basename(file.name);
          if (finalName.toLowerCase().contains('llama-server')) {
            finalName = finalName.toLowerCase().startsWith('llama-server')
                ? (Platform.isWindows ? 'llama-server.exe' : 'llama-server')
                : finalName;
          }
          final finalPath = p.join(destDir, finalName);
          final outFile = File(finalPath);
          await outFile.writeAsBytes(file.content as List<int>);
        }
      }
    }

    if (!File(p.join(destDir, serverExeName)).existsSync()) {
      throw Exception('$serverExeName not found in archive');
    }
  }

  Future<void> _markLlmModelDone(String modelId) async {
    state = state.copyWith(
      phase: DownloadPhase.done,
      activeModelId: modelId,
      progressPercent: 100,
      downloadedLlmModels: {...state.downloadedLlmModels, modelId},
      llmServerReady: true,
    );
  }
}

/// Speed sample for rolling average calculation.
class _SpeedSample {
  const _SpeedSample(this.time, this.bytes);
  final DateTime time;
  final int bytes;
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final modelDownloadProvider =
    NotifierProvider<ModelDownloadNotifier, ModelDownloadState>(
      ModelDownloadNotifier.new,
    );
