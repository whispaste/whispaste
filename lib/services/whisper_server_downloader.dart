/// Whisper-server binary downloader — reads the
/// [WhisperServerManifest], picks the binary that fits the host's
/// platform + GPU via [WhisperBinarySelector], fetches and extracts it.
///
/// The previous version queried the GitHub Releases API directly and
/// matched assets by substring. That broke as soon as a third party
/// reorganised tags. The manifest is now the contract: the CI publishes
/// it (raw + release-asset + bundled fallback) and this class consumes
/// it. No more pattern matching, no more pagination, no more
/// rate-limit-tangenz.
library;

import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

import '../core/logging/app_logger.dart';
import '../core/logging/crash_fingerprints.dart';
import '../core/logging/crash_reporter.dart';
import 'hardware_info_service.dart' as hw;
import 'http_model_fetcher.dart';
import 'whisper_server_manifest.dart';

final _log = AppLogger('WhisperServerDownloader');

// ---------------------------------------------------------------------------
// Progress callback types
// ---------------------------------------------------------------------------

/// Called when a download chunk arrives; mirrors [FetchProgress].
typedef ServerFetchProgressCallback = void Function(FetchProgress progress);

/// Called when extraction starts (so the orchestrator can update UI phase).
typedef ServerExtractingCallback = void Function();

// ---------------------------------------------------------------------------
// WhisperServerDownloader
// ---------------------------------------------------------------------------

/// Downloads, extracts, and installs the whisper-server binary that
/// matches the host platform + GPU per the active manifest.
///
/// Throws [DioException] on user-initiated cancellation.
/// Throws [Exception] when no compatible binary is in the manifest or
/// when every retry exhausts.
class WhisperServerDownloader {
  WhisperServerDownloader({
    HttpModelFetcher? fetcher,
    WhisperServerManifestLoader? manifestLoader,
    WhisperBinarySelector? selector,
  }) : _fetcher = fetcher ?? HttpModelFetcher(),
       _manifestLoader = manifestLoader ?? WhisperServerManifestLoader(),
       _selector = selector ?? const WhisperBinarySelector();

  final HttpModelFetcher _fetcher;
  final WhisperServerManifestLoader _manifestLoader;
  final WhisperBinarySelector _selector;

  // -----------------------------------------------------------------------
  // Public API
  // -----------------------------------------------------------------------

  /// Downloads and installs the whisper-server binary into [destDir].
  ///
  /// [platformOverride] and [archOverride] are forwarded to
  /// [WhisperBinarySelector.select] and exist for testing only
  /// (simulate a specific host platform/arch without running on that hardware).
  Future<void> download({
    required String destDir,
    required String gpuMode,
    ServerFetchProgressCallback? onProgress,
    ServerExtractingCallback? onExtracting,
    @visibleForTesting String? platformOverride,
    @visibleForTesting String? archOverride,
  }) async {
    final gpu = await hw.detectGpu();
    _log.info(
      'Resolving whisper-server binary '
      '(gpu=${gpu.vendor.name}, name="${gpu.name}", '
      'vram=${gpu.vramMB ?? "?"}MB, cuda=${gpu.cudaAvailable}, '
      'vulkan=${gpu.vulkanAvailable}, mode=$gpuMode)',
    );

    final WhisperServerManifest manifest;
    try {
      manifest = await _manifestLoader.load();
    } on Exception catch (e) {
      final msg = 'Manifest load failed: $e';
      _log.warning(msg);
      _reportFailure(
        gpu: gpu,
        gpuMode: gpuMode,
        message: msg,
        type: 'server_download_failed',
        fingerprint: serverDownloadFailed,
      );
      throw Exception(msg);
    }

    final selection = _selector.select(
      manifest: manifest,
      gpu: gpu,
      gpuMode: gpuMode,
      platformOverride: platformOverride,
      archOverride: archOverride,
    );
    if (!selection.hasBinary) {
      final reason =
          selection.reason ?? 'No matching whisper-server binary found';
      _log.warning(reason);
      _reportFailure(
        gpu: gpu,
        gpuMode: gpuMode,
        message: reason,
        type: 'server_download_failed',
        fingerprint: serverDownloadFailed,
        manifestTag: manifest.whisperServerTag,
      );
      throw Exception(reason);
    }

    final binary = selection.binary!;
    _log.info('Selected binary: $binary (url=${binary.url})');

    String? lastError;
    var sawStall = false;
    for (var attempt = 1; attempt <= 2; attempt++) {
      try {
        final zipPath = p.join(destDir, '_whisper-server.zip');
        await _fetcher.fetch(
          url: binary.url,
          destPath: zipPath,
          expectedSize: binary.sizeBytes,
          onProgress: onProgress,
        );

        onExtracting?.call();
        await _extractServerZip(zipPath, destDir);
        await File(zipPath).delete().catchError((_) => File(zipPath));

        await hw.writeServerBinaryInfo(
          destDir,
          gpu,
          sourceRepo: binary.source,
          assetName: Uri.parse(binary.url).pathSegments.lastOrNull ?? '',
        );

        _log.info(
          'whisper-server ready (tag=${manifest.whisperServerTag}, '
          'backend=${binary.backend}, source=${binary.source})',
        );
        return;
      } on DioException catch (e) {
        // User-initiated cancel propagates as-is. Stall-detector cancel
        // is retriable. See HttpStallDetector / PRD Modul 3.
        final isStallCancel =
            e.type == DioExceptionType.cancel &&
            e.message == httpStallCancelMessage;
        if (e.type == DioExceptionType.cancel && !isStallCancel) {
          rethrow;
        }
        if (isStallCancel) sawStall = true;
        lastError = describeDioError(e);
        _log.warning(
          'Server download failed (attempt $attempt, url=${binary.url}): '
          '$lastError',
        );
        if (attempt < 2) {
          await Future<void>.delayed(Duration(seconds: 2 * attempt));
        }
      } on Exception catch (e) {
        lastError = '$e';
        _log.warning(
          'Server download failed (attempt $attempt, url=${binary.url}): $e',
        );
        if (attempt < 2) {
          await Future<void>.delayed(Duration(seconds: 2 * attempt));
        }
      }
    }

    // Downgraded from error → warning to avoid AppLogger's auto-escalate
    // path duplicating the explicit fingerprinted Sentry capture below.
    _log.warning('Could not download whisper-server after retries');
    final finalMessage =
        lastError ?? 'whisper-server download failed (no specific error)';
    _reportFailure(
      gpu: gpu,
      gpuMode: gpuMode,
      message: finalMessage,
      type: sawStall ? 'server_download_stalled' : 'server_download_failed',
      fingerprint: sawStall ? serverDownloadStalled : serverDownloadFailed,
      manifestTag: manifest.whisperServerTag,
      assetUrl: binary.url,
      backend: binary.backend,
    );
    throw Exception(finalMessage);
  }

  // -----------------------------------------------------------------------
  // Sentry reporting
  // -----------------------------------------------------------------------

  void _reportFailure({
    required hw.GpuInfo gpu,
    required String gpuMode,
    required String message,
    required String type,
    required String fingerprint,
    String? manifestTag,
    String? assetUrl,
    String? backend,
  }) {
    CrashReporter.instance?.captureError(
      message: 'whisper-server download failed: $message',
      severity: 'error',
      type: type,
      fingerprint: <String>[fingerprint],
      extras: {
        'platform': Platform.operatingSystem,
        'gpu_mode': gpuMode,
        'gpu_vendor': gpu.vendor.name,
        'manifest_tag': ?manifestTag,
        'asset_url': ?assetUrl,
        'backend': ?backend,
        'last_error': message,
      },
    );
  }

  // -----------------------------------------------------------------------
  // Internal — ZIP extraction (unchanged from the legacy implementation)
  // -----------------------------------------------------------------------

  /// Extracts whisper-server binary and libraries from a ZIP archive.
  ///
  /// Platform-aware: on Windows extracts `.exe`/`.dll`, on macOS/Linux
  /// extracts extensionless executables and `.dylib`/`.so` libraries.
  Future<void> _extractServerZip(String zipPath, String destDir) async {
    final bytes = await File(zipPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    // Clean old server files.
    final destDirObj = Directory(destDir);
    if (destDirObj.existsSync()) {
      for (final f in destDirObj.listSync()) {
        if (f is File) {
          final name = p.basename(f.path).toLowerCase();
          if (isServerFile(name)) {
            await f.delete();
          }
        }
      }
    }

    for (final file in archive) {
      if (file.isFile) {
        final name = p.basename(file.name).toLowerCase();
        if (isExtractableServerFile(name)) {
          // Zip Slip protection.
          final outPath = p.join(destDir, p.basename(file.name));
          if (!p.isWithin(destDir, outPath)) continue;

          // Rename bare server binary → whisper-server if needed.
          String finalName = p.basename(file.name);
          if (Platform.isWindows) {
            if (finalName.toLowerCase() == 'server.exe') {
              finalName = 'whisper-server.exe';
            }
          } else {
            if (finalName.toLowerCase() == 'server') {
              finalName = 'whisper-server';
            }
          }
          final finalPath = p.join(destDir, finalName);
          final outFile = File(finalPath);
          await outFile.writeAsBytes(file.content as List<int>);
        }
      }
    }

    // On Unix, make the binary executable and remove quarantine.
    if (!Platform.isWindows) {
      final serverPath = _whisperServerPathIn(destDir);
      if (File(serverPath).existsSync()) {
        await Process.run('chmod', ['+x', serverPath]);
        // macOS quarantines downloaded files, blocking execution.
        if (Platform.isMacOS) {
          await Process.run('xattr', [
            '-d',
            'com.apple.quarantine',
            serverPath,
          ]);
        }
      }
    }

    // Verify extraction produced the expected binary.
    final expectedPath = _whisperServerPathIn(destDir);
    if (!File(expectedPath).existsSync()) {
      throw Exception('${p.basename(expectedPath)} not found in archive');
    }
  }

  /// Path to the whisper-server binary inside [destDir].
  static String _whisperServerPathIn(String destDir) {
    final name = Platform.isWindows ? 'whisper-server.exe' : 'whisper-server';
    return p.join(destDir, name);
  }

  /// Whether [name] (lowercase) is an old server file to clean before
  /// re-extraction.
  @visibleForTesting
  static bool isServerFile(String name) {
    if (name == 'whisper-server.exe' || name == 'whisper-server') return true;
    if (name.endsWith('.dll') || name.endsWith('.dylib')) return true;
    if (name.endsWith('.so')) return true;
    if (name.endsWith('.metallib')) return true;
    return false;
  }

  /// Whether [name] (lowercase) should be extracted from the ZIP.
  @visibleForTesting
  static bool isExtractableServerFile(String name) {
    if (Platform.isWindows) {
      return name.endsWith('.exe') || name.endsWith('.dll');
    }
    // macOS / Linux: executables have no extension, shared libs are .dylib/.so.
    if (name.endsWith('.dylib') || name.endsWith('.so')) return true;
    if (name.endsWith('.metallib')) return true;
    // Extract extensionless files (the server binary itself).
    if (!name.contains('.')) return true;
    return false;
  }
}
