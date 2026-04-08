/// Model download service — manages downloading STT/LLM models and server
/// binaries from HuggingFace and GitHub with progress, SHA256 verification,
/// and resume support.
library;

import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../core/config/settings_provider.dart';
import '../core/app_info.dart';
import 'hardware_info_service.dart' as hw;
import 'path_service.dart';

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
    sha256:
        '818710568da3ca15689e31a743197b520007872ff9576237bda97bd1b469c3d7',
    description: 'Fastest, lower accuracy',
  ),
  SttModelInfo(
    id: 'whisper-base',
    label: 'Base',
    filename: 'ggml-base-q5_1.bin',
    sizeBytes: 59700000,
    url:
        'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base-q5_1.bin',
    sha256:
        '422f1ae452ade6f30a004d7e5c6a43195e4433bc370bf23fac9cc591f01a8898',
    description: 'Good balance of speed and accuracy',
  ),
  SttModelInfo(
    id: 'whisper-small',
    label: 'Small',
    filename: 'ggml-small-q5_1.bin',
    sizeBytes: 190085487,
    url:
        'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small-q5_1.bin',
    sha256:
        'ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb',
    description: 'Recommended for most users',
  ),
  SttModelInfo(
    id: 'whisper-medium',
    label: 'Medium',
    filename: 'ggml-medium-q5_0.bin',
    sizeBytes: 539212467,
    url:
        'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium-q5_0.bin',
    sha256:
        '19fea4b380c3a618ec4723c3eef2eb785ffba0d0538cf43f8f235e7b3b34220f',
    description: 'High accuracy, needs more RAM',
  ),
  SttModelInfo(
    id: 'whisper-large-v3-turbo',
    label: 'Large v3 Turbo',
    filename: 'ggml-large-v3-turbo-q5_0.bin',
    sizeBytes: 574041195,
    url:
        'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin',
    sha256:
        '394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2',
    description: 'Best speed/quality ratio for large models',
  ),
  SttModelInfo(
    id: 'whisper-large-v3',
    label: 'Large v3',
    filename: 'ggml-large-v3-q5_0.bin',
    sizeBytes: 1081140203,
    url:
        'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-q5_0.bin',
    sha256:
        'd75795ecff3f83b5faa89d1900604ad8c780abd5739fae406de19f23ecd98ad1',
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
// Quality Tiers — user-facing abstraction over raw model names
// ---------------------------------------------------------------------------

/// User-facing quality tiers that abstract away model internals.
enum QualityTier { compact, balanced, premium }

/// Returns the ordered list of models belonging to [tier] (best first).
///
/// Within each tier, models are sorted by descending file size so that
/// [bestModelForTier] always returns the highest-quality option.
List<SttModelInfo> modelsForTier(QualityTier tier) {
  final ids = switch (tier) {
    QualityTier.compact => {'whisper-base', 'whisper-tiny'},
    QualityTier.balanced => {'whisper-medium', 'whisper-small'},
    QualityTier.premium => {'whisper-large-v3-turbo', 'whisper-large-v3'},
  };
  final models = sttModels.where((m) => ids.contains(m.id)).toList()
    ..sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
  return models;
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
/// NVIDIA with CUDA handles large models well at modest VRAM. Intel/AMD
/// Vulkan and CPU-only need higher VRAM margins for the same tier.
QualityTier recommendTier(int vramMB, {hw.GpuVendor? vendor}) {
  // NVIDIA CUDA — dedicated GPU, excellent inference performance.
  if (vendor == hw.GpuVendor.nvidia) {
    if (vramMB >= 2048) return QualityTier.premium;
    if (vramMB >= 512) return QualityTier.balanced;
    return QualityTier.compact;
  }

  // Apple Metal — unified memory, generally performs well.
  if (vendor == hw.GpuVendor.apple) {
    if (vramMB >= 4096) return QualityTier.premium;
    if (vramMB >= 2048) return QualityTier.balanced;
    return QualityTier.compact;
  }

  // Intel/AMD Vulkan or CPU — slower inference, conservative thresholds.
  if (vramMB >= 4096) return QualityTier.premium;
  if (vramMB >= 512) return QualityTier.balanced;
  return QualityTier.compact;
}

/// Returns a user-facing warning when [tier] may perform poorly on [gpu],
/// or `null` if no concerns.
String? tierWarning(QualityTier tier, hw.GpuInfo gpu) {
  if (tier == QualityTier.compact) return null;

  // CPU-only — large models will be very slow.
  if (!gpu.hasGpu) {
    if (tier == QualityTier.premium) {
      return 'Large models are very slow without GPU acceleration. '
          'Consider "Balanced" for better performance.';
    }
    if (tier == QualityTier.balanced) {
      return 'Without a GPU, transcription will be noticeably slower.';
    }
  }

  // Intel/AMD integrated graphics — premium is risky.
  if (tier == QualityTier.premium &&
      (gpu.vendor == hw.GpuVendor.intel || gpu.vendor == hw.GpuVendor.amd)) {
    final vram = gpu.vramMB ?? 0;
    if (vram < 4096) {
      return 'Large models may be slow on integrated graphics. '
          '"Balanced" is recommended for your hardware.';
    }
  }

  return null;
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
  final String? errorMessage;

  /// Set of model IDs whose files exist on disk.
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
      errorMessage: errorMessage,
      downloadedModels: downloadedModels ?? this.downloadedModels,
      serverReady: serverReady ?? this.serverReady,
    );
  }
}

// ---------------------------------------------------------------------------
// Download notifier
// ---------------------------------------------------------------------------

class ModelDownloadNotifier extends Notifier<ModelDownloadState> {
  CancelToken? _cancelToken;
  final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(minutes: 10),
    headers: {'User-Agent': appUserAgent},
  ));

  @override
  ModelDownloadState build() {
    ref.onDispose(() {
      _cancelToken?.cancel('disposed');
      _dio.close();
    });
    // Scan disk for already-downloaded models.
    return _scanExisting();
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
        dev.log('Created STT directory: ${dir.path}', name: 'Download');
      }

      // Phase 1: Ensure whisper-server binary exists.
      if (!state.serverReady) {
        state = state.copyWith(
          activeModelId: modelId,
          phase: DownloadPhase.downloading,
          progressPercent: 0,
          errorMessage: null,
        );
        await _downloadWhisperServer();
      }

      // Phase 2: Download model file.
      state = state.copyWith(
        activeModelId: modelId,
        phase: DownloadPhase.downloading,
        progressPercent: 0,
        bytesDownloaded: 0,
        totalBytes: model.sizeBytes,
      );

      final destPath = p.join(sttDir(), model.filename);
      if (File(destPath).existsSync()) {
        dev.log('Model ${model.id} already exists, verifying…',
            name: 'Download');
        state = state.copyWith(phase: DownloadPhase.verifying);
        final ok = await _verifySha256(destPath, model.sha256);
        if (ok) {
          _markModelDone(model.id);
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
      state = state.copyWith(phase: DownloadPhase.verifying, progressPercent: 99);
      final ok = await _verifySha256(destPath, model.sha256);
      if (!ok) {
        await File(destPath).delete().catchError((_) => File(destPath));
        state = state.copyWith(
          phase: DownloadPhase.error,
          errorMessage: 'SHA256 verification failed — file may be corrupt.',
        );
        return;
      }

      _markModelDone(model.id);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        state = state.copyWith(
          phase: DownloadPhase.idle,
          activeModelId: null,
        );
      } else {
        state = state.copyWith(
          phase: DownloadPhase.error,
          errorMessage: 'Download failed: ${e.message}',
        );
      }
    } on Exception catch (e) {
      state = state.copyWith(
        phase: DownloadPhase.error,
        errorMessage: '$e',
      );
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
  // Private — scanning
  // -----------------------------------------------------------------------

  ModelDownloadState _scanExisting() {
    final downloaded = <String>{};
    final dir = Directory(sttDir());
    if (!dir.existsSync()) {
      // Create on first access so downloads never fail on missing dir.
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
    dev.log(
      'Scan: ${downloaded.length} models, server=${serverExists ? "ready" : "missing"}',
      name: 'Download',
    );
    return ModelDownloadState(
      downloadedModels: downloaded,
      serverReady: serverExists,
    );
  }

  /// Marks the server binary as incompatible and deletes it.
  ///
  /// Called by stt_service when a DLL-not-found crash is detected (wrong
  /// GPU binary variant). After this, `serverReady` is false and the next
  /// model download will fetch the correct binary for the detected GPU.
  Future<void> invalidateServerBinary() async {
    try {
      await hw.deleteServerBinary(sttDir());
    } catch (e) {
      dev.log('Failed to delete server binary: $e', name: 'Download');
    }
    state = state.copyWith(serverReady: false);
  }

  void _markModelDone(String modelId) {
    state = state.copyWith(
      phase: DownloadPhase.done,
      activeModelId: modelId,
      progressPercent: 100,
      downloadedModels: {...state.downloadedModels, modelId},
      serverReady: true,
    );
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
      dev.log('Resuming from byte $startByte', name: 'Download');
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

    final sink = tmpFile.openWrite(mode: startByte > 0 ? FileMode.append : FileMode.write);
    int received = startByte;

    try {
      await for (final chunk in response.data!.stream) {
        sink.add(chunk);
        received += chunk.length;
        final pct = totalBytes > 0 ? (received * 100 ~/ totalBytes) : 0;
        state = state.copyWith(
          progressPercent: pct.clamp(0, 99),
          bytesDownloaded: received,
          totalBytes: totalBytes,
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
    dev.log('Verifying SHA256 of $filePath', name: 'Download');
    final file = File(filePath);
    if (!file.existsSync()) return false;

    final digest = await sha256.bind(file.openRead()).first;
    final actualHash = digest.toString();
    final ok = actualHash == expectedHash;
    if (!ok) {
      dev.log(
        'SHA256 mismatch: expected=$expectedHash actual=$actualHash',
        name: 'Download',
      );
    }
    return ok;
  }

  // -----------------------------------------------------------------------
  // Private — whisper-server binary download
  // -----------------------------------------------------------------------

  Future<void> _downloadWhisperServer() async {
    // Log detected GPU for download debugging.
    final gpu = await hw.detectGpu();
    dev.log(
      'Downloading whisper-server binary… '
      '(gpu=${gpu.vendor.name}, name="${gpu.name}", '
      'cuda=${gpu.cudaAvailable})',
      name: 'Download',
    );

    // Determine GPU mode for asset selection.
    final settings =
        ref.read(settingsProvider).value ?? AppSettings.defaults;
    final gpuMode = settings.gpuAcceleration;

    // Try WhisPaste-owned releases first, then upstream.
    const repos = [
      ('whispaste', 'whispaste'),
      ('ggml-org', 'whisper.cpp'),
    ];

    for (final (owner, repo) in repos) {
      try {
        final assetUrl = await _findServerAsset(
          owner: owner,
          repo: repo,
          gpuMode: gpuMode,
          isWhisPaste: owner == 'whispaste',
        );
        if (assetUrl == null) continue;

        // Download ZIP to temp. Size varies dramatically by backend:
        // CPU/BLAS ~17 MB, Vulkan ~30 MB, CUDA 12 ~460 MB.
        final isCuda = assetUrl.contains('cuda') || assetUrl.contains('cublas');
        final estimatedSize = isCuda ? 460 * 1024 * 1024 : 30 * 1024 * 1024;
        final zipPath = p.join(sttDir(), '_whisper-server.zip');
        await _downloadFile(
          url: assetUrl,
          destPath: zipPath,
          expectedSize: estimatedSize,
        );

        state = state.copyWith(phase: DownloadPhase.extracting);

        // Extract.
        await _extractServerZip(zipPath, sttDir());
        await File(zipPath).delete().catchError((_) => File(zipPath));

        state = state.copyWith(serverReady: true);
        dev.log('whisper-server ready', name: 'Download');
        return;
      } on Exception catch (e) {
        dev.log('Failed from $owner/$repo: $e', name: 'Download');
        continue;
      }
    }

    throw Exception('Could not download whisper-server from any source.');
  }

  /// Queries GitHub releases API and finds the best matching asset.
  Future<String?> _findServerAsset({
    required String owner,
    required String repo,
    required String gpuMode,
    required bool isWhisPaste,
  }) async {
    final apiUrl =
        'https://api.github.com/repos/$owner/$repo/releases/latest';

    final response = await _dio.get<Map<String, dynamic>>(
      apiUrl,
      cancelToken: _cancelToken,
      options: Options(headers: {'Accept': 'application/vnd.github.v3+json'}),
    );

    final assets = (response.data?['assets'] as List<dynamic>?) ?? [];
    if (assets.isEmpty) return null;

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
          dev.log(
            'Selected server asset: $name (pattern=$pattern, '
            'arch=$archPattern, repo=$owner/$repo)',
            name: 'Download',
          );
          return assetMap['browser_download_url'] as String?;
        }
      }
    }

    dev.log(
      'No matching server asset in $owner/$repo '
      '(patterns=$patterns, arch=$archPattern, '
      'assets=${assets.map((a) => (a as Map)['name']).toList()})',
      name: 'Download',
    );
    return null;
  }

  Future<List<String>> _serverAssetPatterns(String gpuMode, bool isWhisPaste) async {
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
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final modelDownloadProvider =
    NotifierProvider<ModelDownloadNotifier, ModelDownloadState>(
  ModelDownloadNotifier.new,
);
