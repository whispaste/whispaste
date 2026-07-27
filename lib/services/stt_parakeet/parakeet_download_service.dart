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

import '../../core/logging/app_logger.dart';
import '../http_model_fetcher.dart';
import 'parakeet_model_registry.dart';

final _log = AppLogger('ParakeetDownload');

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
    if (parakeetModelFilesExistSync()) {
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

    for (var i = 0; i < parakeetModelFiles.length; i++) {
      final file = parakeetModelFiles[i];
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
        _log.error('Download failed for ${file.filename}: $description');
        state = state.copyWith(
          phase: ParakeetDownloadPhase.error,
          errorMessage: 'Download failed: $description',
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

    state = state.copyWith(
      phase: ParakeetDownloadPhase.done,
      progressPercent: 100,
      installed: true,
    );
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
