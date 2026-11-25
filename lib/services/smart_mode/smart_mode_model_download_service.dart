/// Smart-Mode model download service — downloads the local Gemma-4-E2B-it
/// GGUF used by [SmartModeFfiEngine].
///
/// Deliberately parallel to `model_download_service.dart` rather than
/// extending it: [ModelDownloadNotifier._markModelDone] auto-writes the
/// STT-specific `sttModel` setting, which has nothing to do with Smart Mode.
/// This notifier reuses the same generic, already-extracted transport
/// ([HttpModelFetcher]) and verification ([FileVerificationService]) layers,
/// but activates its own [SmartModeSettings] state instead.
library;

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/logging/app_logger.dart';
import '../../core/models/bundled_model_catalog.dart';
import '../../core/models/model_catalog.dart';
import '../download_disk_space.dart';
import '../download_fragment_guard.dart';
import '../download_error_kind.dart';
import '../download_tls_failure.dart';
import '../file_verification_service.dart';
import '../free_disk_space.dart';
import '../http_model_fetcher.dart';
import '../model_install_check.dart';
import '../model_download_service.dart' show modelDeleteFailedError;
import '../tmp_reaper.dart';
import 'smart_mode_ffi_engine.dart' show smartModeModelPath;

final _log = AppLogger('SmartModeDownload');

// ---------------------------------------------------------------------------
// Model registry — single entry for now (Gemma-4-E2B-it Q4_K_M).
// ---------------------------------------------------------------------------

/// The Smart-Mode local model: a single-file [CatalogModel] of kind `llm`.
typedef SmartModeModelInfo = CatalogModel;

/// The Smart-Mode model (Gemma 4 E2B, Q4_K_M), from the bundled catalog.
final SmartModeModelInfo smartModeModel = bundledModelCatalog.byId(
  CatalogIds.gemma4E2b,
);

/// `<appDataDir>/models/smart_mode/` — see [smartModeModelPath].
String smartModeModelDir() => p.dirname(smartModeModelPath());

// ---------------------------------------------------------------------------
// Download state
// ---------------------------------------------------------------------------

enum SmartModeDownloadPhase { idle, downloading, verifying, done, error }

class SmartModeDownloadState {
  const SmartModeDownloadState({
    this.phase = SmartModeDownloadPhase.idle,
    this.progressPercent = 0,
    this.bytesDownloaded = 0,
    this.totalBytes = 0,
    this.speedBytesPerSec = 0,
    this.etaSeconds,
    this.errorMessage,
    this.errorKind,
    this.modelDownloaded = false,
    this.scanned = true,
  });

  final SmartModeDownloadPhase phase;
  final int progressPercent;
  final int bytesDownloaded;
  final int totalBytes;
  final double speedBytesPerSec;
  final int? etaSeconds;
  final String? errorMessage;

  /// Category of [errorMessage] for the user-facing text
  /// (`downloadFailureText`); null for a disk-space code or no error.
  final DownloadErrorKind? errorKind;

  /// Whether the model file exists on disk (updated by the initial async
  /// disk scan and by [SmartModeDownloadNotifier.deleteModel]).
  final bool modelDownloaded;

  /// Whether [modelDownloaded] is known: `false` only until the notifier's
  /// initial disk scan has landed, so the text model does not read as
  /// missing for the first moments after start (UIA-XP-7-05).
  final bool scanned;

  bool get isError => phase == SmartModeDownloadPhase.error;
  bool get isBusy =>
      phase == SmartModeDownloadPhase.downloading ||
      phase == SmartModeDownloadPhase.verifying;

  SmartModeDownloadState copyWith({
    SmartModeDownloadPhase? phase,
    int? progressPercent,
    int? bytesDownloaded,
    int? totalBytes,
    double? speedBytesPerSec,
    int? etaSeconds,
    String? errorMessage,
    DownloadErrorKind? errorKind,
    bool? modelDownloaded,
    bool? scanned,
  }) {
    return SmartModeDownloadState(
      phase: phase ?? this.phase,
      progressPercent: progressPercent ?? this.progressPercent,
      bytesDownloaded: bytesDownloaded ?? this.bytesDownloaded,
      totalBytes: totalBytes ?? this.totalBytes,
      speedBytesPerSec: speedBytesPerSec ?? this.speedBytesPerSec,
      etaSeconds: etaSeconds ?? this.etaSeconds,
      errorMessage: errorMessage,
      errorKind: errorKind,
      modelDownloaded: modelDownloaded ?? this.modelDownloaded,
      scanned: scanned ?? this.scanned,
    );
  }
}

// ---------------------------------------------------------------------------
// Disk scanner
// ---------------------------------------------------------------------------

Future<bool> _scanExistingModelAsync(
  Future<bool> Function(String path) fileExists,
) async {
  final dir = Directory(smartModeModelDir());
  if (!await dir.exists()) {
    try {
      await dir.create(recursive: true);
    } on FileSystemException catch (e) {
      _log.warning('Failed to create Smart Mode model directory', e);
    }
  }
  final exists = await fileExists(
    p.join(smartModeModelDir(), smartModeModel.filename),
  );
  _log.info('Scan: Smart Mode model downloaded=$exists');
  return exists;
}

// ---------------------------------------------------------------------------
// Download notifier
// ---------------------------------------------------------------------------

class SmartModeDownloadNotifier extends Notifier<SmartModeDownloadState> {
  @visibleForTesting
  HttpModelFetcher? fetcherOverride;

  @visibleForTesting
  FileVerificationService? verifierOverride;

  @visibleForTesting
  Future<bool> Function(String path)? existsHookOverride;

  /// The model counts as installed only with its pinned size.
  Future<bool> Function(String path) get _checker =>
      existsHookOverride ??
      (path) => fileHasPinnedSize(path, smartModeModel.file.sizeBytes);

  bool _mounted = false;
  Completer<void>? _initialScanCompleter;

  // One fetcher per notifier: cancel and dispose must reach the one that is
  // downloading (UIA-RT-05).
  late final HttpModelFetcher _fetcher = fetcherOverride ?? HttpModelFetcher();

  FileVerificationService get _verifier =>
      verifierOverride ?? const FileVerificationService();

  @override
  SmartModeDownloadState build() {
    _mounted = true;
    _initialScanCompleter = Completer<void>();
    final checker = _checker;

    ref.onDispose(() {
      _mounted = false;
      _fetcher.cancel('disposed');
      if (!(_initialScanCompleter?.isCompleted ?? true)) {
        _initialScanCompleter!.complete();
      }
    });

    // Deferred off the build frame — same rationale as ModelDownloadNotifier
    // (avoids UI-thread stalls from the blocking disk scan).
    Future.microtask(() async {
      try {
        final downloaded = await _scanExistingModelAsync(checker);
        if (_mounted) {
          state = state.copyWith(modelDownloaded: downloaded, scanned: true);
        }
      } catch (e, st) {
        _log.warning('Initial disk scan failed', e, st);
        // An unreadable disk counts as known-missing, not as unknown forever.
        if (_mounted) state = state.copyWith(scanned: true);
      } finally {
        if (!(_initialScanCompleter?.isCompleted ?? true)) {
          _initialScanCompleter!.complete();
        }
        _initialScanCompleter = null;
      }
    });

    return const SmartModeDownloadState(scanned: false);
  }

  Future<void> awaitInitialScan() async {
    await _initialScanCompleter?.future;
  }

  /// Downloads the Smart-Mode model. Orchestrates: Fetch → Verify → Done.
  Future<void> downloadModel() async {
    await awaitInitialScan();
    if (!_mounted) return;
    if (state.isBusy) return;

    final destPath = p.join(smartModeModelDir(), smartModeModel.filename);

    try {
      final dir = Directory(smartModeModelDir());
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }

      if (File(destPath).existsSync()) {
        state = state.copyWith(
          phase: SmartModeDownloadPhase.verifying,
          errorMessage: null,
        );
        final result = await _verifier.verifyStamped(
          File(destPath),
          smartModeModel.sha256,
        );
        if (result is VerificationOk) {
          await clearFragmentIdentity(destPath);
          _markDone();
          return;
        }
        await File(destPath).delete(); // Hash mismatch — re-download.
      }

      state = state.copyWith(
        phase: SmartModeDownloadPhase.downloading,
        progressPercent: 0,
        bytesDownloaded: 0,
        totalBytes: smartModeModel.sizeBytes,
        errorMessage: null,
      );

      final shortage = await checkDownloadDiskSpace(
        dir: smartModeModelDir(),
        downloadBytes: smartModeModel.sizeBytes,
        probe: ref.read(freeDiskSpaceProbeProvider),
      );
      if (shortage != null) {
        _log.warning(
          'Not enough disk space for Smart Mode model: '
          'needs ${shortage.neededBytes} B, free ${shortage.freeBytes} B',
        );
        state = state.copyWith(
          phase: SmartModeDownloadPhase.error,
          errorMessage: shortage.errorCode,
        );
        return;
      }

      try {
        await _fetcher.fetchVerified(
          sources: smartModeModel.sources,
          destPath: destPath,
          expectedSize: smartModeModel.sizeBytes,
          expectedSha256: smartModeModel.sha256,
          verifier: _verifier,
          onProgress: (prog) => state = state.copyWith(
            progressPercent: prog.progressPercent,
            bytesDownloaded: prog.bytesReceived,
            totalBytes: prog.totalBytes,
            speedBytesPerSec: prog.speedBytesPerSec,
            etaSeconds: prog.etaSeconds,
          ),
          onVerifying: () => state = state.copyWith(
            phase: SmartModeDownloadPhase.verifying,
            progressPercent: 99,
          ),
        );
      } on DownloadChecksumException {
        state = state.copyWith(
          phase: SmartModeDownloadPhase.error,
          errorMessage: 'SHA256 verification failed — file may be corrupt.',
          errorKind: DownloadErrorKind.checksum,
        );
        return;
      }

      _markDone();
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        state = state.copyWith(
          phase: SmartModeDownloadPhase.idle,
          progressPercent: 0,
        );
      } else {
        final tls = isTlsDownloadFailure(e);
        final msg = 'Download failed: ${describeDioError(e)}';
        isConnectionDownloadFailure(e) ? _log.warning(msg) : _log.error(msg);
        state = state.copyWith(
          phase: SmartModeDownloadPhase.error,
          errorMessage: tls ? downloadTlsErrorCode : msg,
          errorKind: classifyDownloadError(e),
        );
      }
    } on Exception catch (e) {
      isConnectionDownloadFailure(e)
          ? _log.warning('Download error: $e')
          : _log.error('Download error: $e');
      state = state.copyWith(
        phase: SmartModeDownloadPhase.error,
        errorMessage: '$e',
        errorKind: classifyDownloadError(e),
      );
    }
  }

  void cancelDownload() {
    _fetcher.cancel('user cancelled');
    state = state.copyWith(
      phase: SmartModeDownloadPhase.idle,
      progressPercent: 0,
    );
  }

  Future<void> deleteModel() async {
    final file = File(p.join(smartModeModelDir(), smartModeModel.filename));
    try {
      if (file.existsSync()) await file.delete();
    } on FileSystemException catch (e) {
      // Held open (Windows) or no permission: keep it listed, say so.
      _log.warning('Smart Mode model not deleted: ${e.message}');
      state = state.copyWith(
        phase: SmartModeDownloadPhase.error,
        errorMessage: modelDeleteFailedError,
        errorKind: DownloadErrorKind.storage,
      );
      return;
    }
    state = state.copyWith(modelDownloaded: false);
  }

  void _markDone() {
    state = state.copyWith(
      phase: SmartModeDownloadPhase.done,
      progressPercent: 100,
      modelDownloaded: true,
    );
    unawaited(sweepOrphanedTmpFiles(directory: smartModeModelDir()));
  }
}

final smartModeDownloadProvider =
    NotifierProvider<SmartModeDownloadNotifier, SmartModeDownloadState>(
      SmartModeDownloadNotifier.new,
    );
