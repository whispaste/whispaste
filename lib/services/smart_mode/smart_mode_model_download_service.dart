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
import '../file_verification_service.dart';
import '../http_model_fetcher.dart';
import '../model_download_service.dart' show formatModelSizeLabel;
import '../tmp_reaper.dart';
import 'smart_mode_ffi_engine.dart' show smartModeModelPath;

final _log = AppLogger('SmartModeDownload');

// ---------------------------------------------------------------------------
// Model registry — single entry for now (Gemma-4-E2B-it Q4_K_M).
// ---------------------------------------------------------------------------

/// Metadata for the Smart-Mode local model.
///
/// Size/hash are ground-truth values read from the HuggingFace LFS metadata
/// of `unsloth/gemma-4-E2B-it-GGUF` (`.scratch/smart-mode-v2/
/// research-gemma-4-e2b-license-and-config.md` — 3,106,738,272 bytes
/// confirmed by direct file inspection during the license/config research
/// spike).
class SmartModeModelInfo {
  const SmartModeModelInfo({
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

  String get sizeLabel => formatModelSizeLabel(sizeBytes);
}

const smartModeModel = SmartModeModelInfo(
  id: 'gemma-4-E2B-it-Q4_K_M',
  label: 'Gemma-4-E2B-it (Q4_K_M)',
  filename: 'gemma-4-E2B-it-Q4_K_M.gguf',
  sizeBytes: 3106738272,
  url:
      'https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF/resolve/main/gemma-4-E2B-it-Q4_K_M.gguf',
  sha256: '740185b21d22ceb83a11c3aa62ad5842ef32c70f6096d756bbee85a1e4ec34b8',
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
    this.modelDownloaded = false,
  });

  final SmartModeDownloadPhase phase;
  final int progressPercent;
  final int bytesDownloaded;
  final int totalBytes;
  final double speedBytesPerSec;
  final int? etaSeconds;
  final String? errorMessage;

  /// Whether the model file exists on disk (updated by the initial async
  /// disk scan and by [SmartModeDownloadNotifier.deleteModel]).
  final bool modelDownloaded;

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
    bool? modelDownloaded,
  }) {
    return SmartModeDownloadState(
      phase: phase ?? this.phase,
      progressPercent: progressPercent ?? this.progressPercent,
      bytesDownloaded: bytesDownloaded ?? this.bytesDownloaded,
      totalBytes: totalBytes ?? this.totalBytes,
      speedBytesPerSec: speedBytesPerSec ?? this.speedBytesPerSec,
      etaSeconds: etaSeconds ?? this.etaSeconds,
      errorMessage: errorMessage,
      modelDownloaded: modelDownloaded ?? this.modelDownloaded,
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

  Future<bool> Function(String path) get _checker =>
      existsHookOverride ?? (path) => File(path).exists();

  bool _mounted = false;
  Completer<void>? _initialScanCompleter;

  HttpModelFetcher get _fetcher => fetcherOverride ?? HttpModelFetcher();

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
          state = state.copyWith(modelDownloaded: downloaded);
        }
      } catch (e, st) {
        _log.warning('Initial disk scan failed', e, st);
      } finally {
        if (!(_initialScanCompleter?.isCompleted ?? true)) {
          _initialScanCompleter!.complete();
        }
        _initialScanCompleter = null;
      }
    });

    return const SmartModeDownloadState();
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
        final result = await _verifier.verify(
          File(destPath),
          smartModeModel.sha256,
        );
        if (result is VerificationOk) {
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

      await _fetcher.fetch(
        url: smartModeModel.url,
        destPath: destPath,
        expectedSize: smartModeModel.sizeBytes,
        onProgress: (prog) => state = state.copyWith(
          progressPercent: prog.progressPercent,
          bytesDownloaded: prog.bytesReceived,
          totalBytes: prog.totalBytes,
          speedBytesPerSec: prog.speedBytesPerSec,
          etaSeconds: prog.etaSeconds,
        ),
      );

      state = state.copyWith(
        phase: SmartModeDownloadPhase.verifying,
        progressPercent: 99,
      );
      final result = await _verifier.verify(
        File(destPath),
        smartModeModel.sha256,
      );
      if (result is! VerificationOk) {
        await File(destPath).delete().catchError((_) => File(destPath));
        state = state.copyWith(
          phase: SmartModeDownloadPhase.error,
          errorMessage: 'SHA256 verification failed — file may be corrupt.',
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
        final msg = 'Download failed: ${describeDioError(e)}';
        _log.error(msg);
        state = state.copyWith(
          phase: SmartModeDownloadPhase.error,
          errorMessage: msg,
        );
      }
    } on Exception catch (e) {
      _log.error('Download error: $e');
      state = state.copyWith(
        phase: SmartModeDownloadPhase.error,
        errorMessage: '$e',
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
    if (file.existsSync()) {
      await file.delete();
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
