/// Downloads the Parakeet (sherpa_onnx) model bundle — four files fetched
/// sequentially via the existing [HttpModelFetcher] transport. Kept as a
/// standalone notifier (mirroring [ModelDownloadState]'s shape) rather than
/// folding into `model_download_service.dart`, so the whisper single-file
/// download path is untouched.
///
/// Integrity: see [parakeet_model_registry.dart] doc comment — no SHA-256 is
/// pinned for this repo (HuggingFace Xet storage does not expose one via a
/// simple HTTP call), so verification here is a byte-size sanity check only.
library;

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/settings_provider.dart';
import '../../core/logging/app_logger.dart';
import '../http_model_fetcher.dart';
import '../model_download_service.dart' show formatModelSizeLabel;
import '../tmp_reaper.dart';
import 'parakeet_gguf_model.dart';
import 'parakeet_gpu_policy.dart';
import 'parakeet_model_registry.dart';

final _log = AppLogger('ParakeetDownload');

/// Whether the GPU engine, and with it the GGUF download, applies for this
/// `behavior.gpuAcceleration` value. Used by the size labels in the UI.
bool parakeetGpuWantedForSetting(String? gpuAcceleration) => parakeetGpuWanted(
  gpuAccelerationAllowed: (gpuAcceleration ?? 'auto') != 'disabled',
);

/// Bytes the Parakeet download puts on disk. The sherpa bundle is always
/// fetched, because it is the fallback when the GPU fails, so a GPU machine
/// stores both files: the sherpa bundle plus the GGUF model.
int parakeetDownloadBytes({required bool gpuWanted}) =>
    parakeetModelTotalBytes + (gpuWanted ? parakeetGgufActive.sizeBytes : 0);

/// Human-readable [parakeetDownloadBytes], e.g. `"639 MB"` or `"1.2 GB"`.
String parakeetDownloadSizeLabel({required bool gpuWanted}) =>
    formatModelSizeLabel(parakeetDownloadBytes(gpuWanted: gpuWanted));

/// Progress/phase state for the Parakeet bundle download — deliberately the
/// same shape as `DownloadPhase`/`ModelDownloadState` in
/// `model_download_service.dart` so the UI layer can treat both uniformly.
enum ParakeetDownloadPhase { idle, downloading, verifying, done, error }

class ParakeetDownloadState {
  const ParakeetDownloadState({
    this.phase = ParakeetDownloadPhase.idle,
    this.currentFileIndex = 0,
    this.progressPercent = 0,
    this.bytesDownloaded = 0,
    this.totalBytes = 0,
    this.errorMessage,
    this.installed = false,
  });

  final ParakeetDownloadPhase phase;

  /// Index (0-based) into [parakeetModelFiles] currently downloading.
  final int currentFileIndex;
  final int progressPercent;
  final int bytesDownloaded;
  final int totalBytes;
  final String? errorMessage;

  /// Whether all four bundle files are present on disk.
  final bool installed;

  bool get isBusy =>
      phase == ParakeetDownloadPhase.downloading ||
      phase == ParakeetDownloadPhase.verifying;

  ParakeetDownloadState copyWith({
    ParakeetDownloadPhase? phase,
    int? currentFileIndex,
    int? progressPercent,
    int? bytesDownloaded,
    int? totalBytes,
    String? errorMessage,
    bool? installed,
  }) => ParakeetDownloadState(
    phase: phase ?? this.phase,
    currentFileIndex: currentFileIndex ?? this.currentFileIndex,
    progressPercent: progressPercent ?? this.progressPercent,
    bytesDownloaded: bytesDownloaded ?? this.bytesDownloaded,
    totalBytes: totalBytes ?? this.totalBytes,
    errorMessage: errorMessage,
    installed: installed ?? this.installed,
  );
}

class ParakeetDownloadNotifier extends Notifier<ParakeetDownloadState> {
  /// Injected fetcher — override in tests to avoid real network calls.
  @visibleForTesting
  HttpModelFetcher? fetcherOverride;

  HttpModelFetcher get _fetcher => fetcherOverride ?? HttpModelFetcher();

  @override
  ParakeetDownloadState build() {
    ref.onDispose(() => _fetcher.cancel('disposed'));
    return ParakeetDownloadState(installed: parakeetModelFilesExistSync());
  }

  /// Downloads every missing bundle file, in order. No-op if already
  /// installed or a download is already in flight.
  Future<void> downloadBundle() async {
    if (state.isBusy) return;
    if (parakeetModelFilesExistSync() && (!_gpuWanted() || _ggufPresent())) {
      state = state.copyWith(
        phase: ParakeetDownloadPhase.done,
        installed: true,
      );
      return;
    }

    final dir = Directory(parakeetModelDir());
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    state = state.copyWith(
      phase: ParakeetDownloadPhase.downloading,
      currentFileIndex: 0,
      progressPercent: 0,
      errorMessage: null,
    );

    final files = effectiveParakeetModelFiles();
    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      final destPath = parakeetModelFilePath(file.filename);

      if (File(destPath).existsSync() &&
          File(destPath).lengthSync() == file.sizeBytes) {
        continue; // Already downloaded and size matches — skip.
      }

      state = state.copyWith(
        currentFileIndex: i,
        progressPercent: 0,
        bytesDownloaded: 0,
        totalBytes: file.sizeBytes,
      );

      try {
        await _fetcher.fetch(
          url: file.url,
          destPath: destPath,
          expectedSize: file.sizeBytes,
          onProgress: (prog) => state = state.copyWith(
            progressPercent: prog.progressPercent,
            bytesDownloaded: prog.bytesReceived,
            totalBytes: prog.totalBytes,
          ),
        );
      } on DioException catch (e) {
        if (e.type == DioExceptionType.cancel) {
          state = state.copyWith(phase: ParakeetDownloadPhase.idle);
          return;
        }
        final description = _describeDioError(e);
        // A connection the fetcher could not resume is the user's network,
        // not a defect — the partial file stays and a retry resumes it.
        final log = e.type == DioExceptionType.connectionError
            ? _log.warning
            : _log.error;
        log('Download failed for ${file.filename}: $description');
        state = state.copyWith(
          phase: ParakeetDownloadPhase.error,
          errorMessage: 'Download failed: $description',
        );
        return;
      } on Exception catch (e) {
        // The UI starts downloads fire-and-forget, so anything rethrown here
        // would be an unhandled error and leave the UI stuck "downloading".
        _log.error('Download failed for ${file.filename}: $e');
        state = state.copyWith(
          phase: ParakeetDownloadPhase.error,
          errorMessage: 'Download failed: $e',
        );
        return;
      }

      // Size sanity check (no SHA-256 available for this repo — see the
      // library doc comment on parakeet_model_registry.dart).
      state = state.copyWith(phase: ParakeetDownloadPhase.verifying);
      final actualSize = await File(destPath).length();
      if (actualSize != file.sizeBytes) {
        await File(destPath).delete();
        _log.warning(
          'Size mismatch for ${file.filename}: expected=${file.sizeBytes} '
          'actual=$actualSize — deleted, re-download required.',
        );
        state = state.copyWith(
          phase: ParakeetDownloadPhase.error,
          errorMessage: 'Downloaded file size mismatch: ${file.filename}',
        );
        return;
      }
    }

    // GPU engine model: fetched only where the GPU backend is wanted.
    if (_gpuWanted() && !_ggufPresent()) {
      if (!await _downloadGguf(slot: files.length)) return;
    }

    state = state.copyWith(
      phase: ParakeetDownloadPhase.done,
      progressPercent: 100,
      installed: true,
    );

    // Mirrors `ModelDownloadNotifier._markModelDone`'s post-download sweep:
    // reap any OTHER orphaned `.tmp` fragment left in the bundle directory
    // (e.g. from an earlier abandoned attempt) now that this download
    // finished cleanly (fire-and-forget).
    unawaited(sweepOrphanedTmpFiles(directory: parakeetModelDir()));
  }

  /// Downloads and verifies the GGUF for the GPU engine. Returns `false` when
  /// the download was cancelled or failed; [state] then carries the outcome.
  /// The SHA-256 check runs right after download, so a corrupt file is caught
  /// here and not on the first dictation.
  Future<bool> _downloadGguf({required int slot}) async {
    final gguf = parakeetGgufActive;
    state = state.copyWith(
      phase: ParakeetDownloadPhase.downloading,
      currentFileIndex: slot,
      progressPercent: 0,
      bytesDownloaded: 0,
      totalBytes: gguf.sizeBytes,
    );
    try {
      await downloadParakeetGguf(
        fetcher: _fetcher,
        file: gguf,
        onProgress: (prog) => state = state.copyWith(
          progressPercent: prog.progressPercent,
          bytesDownloaded: prog.bytesReceived,
          totalBytes: prog.totalBytes,
        ),
      );
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        state = state.copyWith(phase: ParakeetDownloadPhase.idle);
        return false;
      }
      final description = _describeDioError(e);
      _log.warning('GGUF download failed: $description');
      state = state.copyWith(
        phase: ParakeetDownloadPhase.error,
        errorMessage: 'Download failed: $description',
      );
      return false;
    } on Exception catch (e) {
      _log.error('GGUF download failed: $e');
      state = state.copyWith(
        phase: ParakeetDownloadPhase.error,
        errorMessage: 'Download failed: $e',
      );
      return false;
    }
    state = state.copyWith(phase: ParakeetDownloadPhase.verifying);
    final check = await verifyParakeetGguf(parakeetGgufPath(gguf), gguf);
    if (check != ParakeetGgufCheck.ok) {
      final file = File(parakeetGgufPath(gguf));
      if (file.existsSync()) file.deleteSync();
      _log.warning('GGUF verification failed: ${check.name} — deleted');
      state = state.copyWith(
        phase: ParakeetDownloadPhase.error,
        errorMessage: 'Downloaded model failed verification (${check.name})',
      );
      return false;
    }
    return true;
  }

  bool _gpuAccelerationAllowed() =>
      (ref.read(settingsProvider).value?.behavior.gpuAcceleration ?? 'auto') !=
      'disabled';

  bool _gpuWanted() =>
      parakeetGpuWanted(gpuAccelerationAllowed: _gpuAccelerationAllowed());

  bool _ggufPresent() {
    final file = File(parakeetGgufPath());
    return file.existsSync() &&
        file.lengthSync() == parakeetGgufActive.sizeBytes;
  }

  void cancelDownload() {
    _fetcher.cancel('user cancelled');
    state = state.copyWith(
      phase: ParakeetDownloadPhase.idle,
      progressPercent: 0,
    );
  }

  /// Deletes the whole bundle directory.
  Future<void> deleteBundle() async {
    // Cancel any in-flight download first — on Windows, deleting a directory
    // with open file handles throws (found by cross-review).
    _fetcher.cancel('bundle deleted');
    try {
      final dir = Directory(parakeetModelDir());
      if (dir.existsSync()) {
        await dir.delete(recursive: true);
      }
      state = state.copyWith(
        installed: false,
        phase: ParakeetDownloadPhase.idle,
      );
    } on FileSystemException catch (e) {
      _log.warning('Failed to delete Parakeet bundle: $e');
      state = state.copyWith(
        phase: ParakeetDownloadPhase.error,
        errorMessage: 'Delete failed: ${e.message}',
      );
    }
  }
}

final parakeetDownloadProvider =
    NotifierProvider<ParakeetDownloadNotifier, ParakeetDownloadState>(
      ParakeetDownloadNotifier.new,
    );

/// Describes a [DioException] for display/logging. `e.message` is `null`
/// for many real failures (e.g. connection errors wrapping a lower-level
/// `SocketException`) — surfacing that as the literal string "null"
/// (FLUTTER_WHISPASTE-80) told users and Sentry nothing about what actually
/// failed. Falls back to the wrapped cause, then the exception type, so
/// there is always *some* diagnostic detail.
String _describeDioError(DioException e) =>
    e.message ?? e.error?.toString() ?? 'network error (${e.type.name})';
