/// Whisper-server binary downloader — fetches the platform-appropriate
/// whisper-server binary from GitHub releases, extracts it, and verifies
/// the result.
///
/// Extracted from [ModelDownloadNotifier] so that the binary-download logic
/// is independently testable and reusable without depending on Riverpod state.
library;

import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

import '../core/app_info.dart';
import '../core/logging/app_logger.dart';
import 'hardware_info_service.dart' as hw;
import 'http_model_fetcher.dart';

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

/// Downloads, extracts, and installs the whisper-server binary.
///
/// The caller supplies:
/// - a [fetcher] (or the default is used) for the actual HTTP download.
/// - an [apiDio] (or the default is used) for GitHub API requests.
/// - [onProgress] callback for download progress updates.
/// - [onExtracting] callback fired just before ZIP extraction begins.
///
/// Throws [DioException] on network errors (including cancellation).
/// Throws [Exception] when no compatible binary can be found or extracted.
class WhisperServerDownloader {
  WhisperServerDownloader({HttpModelFetcher? fetcher, Dio? apiDio})
    : _fetcher = fetcher ?? HttpModelFetcher(),
      _apiDio = apiDio ?? _defaultApiDio();

  final HttpModelFetcher _fetcher;
  final Dio _apiDio;
  CancelToken? _apiCancelToken;

  // -----------------------------------------------------------------------
  // Public API
  // -----------------------------------------------------------------------

  /// Downloads and installs the whisper-server binary into [destDir].
  ///
  /// [gpuMode] is the user's GPU-acceleration setting (from AppSettings).
  /// [onProgress] receives streaming download progress events.
  /// [onExtracting] is called once, just before ZIP extraction begins.
  Future<void> download({
    required String destDir,
    required String gpuMode,
    ServerFetchProgressCallback? onProgress,
    ServerExtractingCallback? onExtracting,
  }) async {
    final gpu = await hw.detectGpu();
    _log.info(
      'Downloading whisper-server binary '
      '(gpu=${gpu.vendor.name}, name="${gpu.name}", '
      'vram=${gpu.vramMB ?? "?"}MB, cuda=${gpu.cudaAvailable}, '
      'vulkan=${gpu.vulkanAvailable})',
    );

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
          final zipPath = p.join(destDir, '_whisper-server.zip');
          await _fetcher.fetch(
            url: assetUrl,
            destPath: zipPath,
            expectedSize: estimatedSize,
            onProgress: onProgress,
          );

          onExtracting?.call();

          await _extractServerZip(zipPath, destDir);
          await File(zipPath).delete().catchError((_) => File(zipPath));

          // Write metadata so startup validation can verify compatibility
          // without relying on DLL heuristics alone.
          final assetName = Uri.parse(assetUrl).pathSegments.lastOrNull ?? '';
          await hw.writeServerBinaryInfo(
            destDir,
            gpu,
            sourceRepo: '$owner/$repo',
            assetName: assetName,
          );

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

  // -----------------------------------------------------------------------
  // Internal — GitHub release queries
  // -----------------------------------------------------------------------

  /// Queries GitHub releases API and finds the best matching asset URL.
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
        _apiCancelToken = CancelToken();
        response = await _apiDio.get<Map<String, dynamic>>(
          apiUrl,
          cancelToken: _apiCancelToken,
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

    final assets = (releaseData?['assets'] as List<dynamic>?) ?? [];
    if (assets.isEmpty) {
      _log.info('No assets in $owner/$repo release');
      return null;
    }

    // Build priority list of asset name patterns based on detected GPU.
    final gpu = await hw.detectGpu();
    final patterns = hw.serverAssetPatterns(gpu, gpuMode, isWhisPaste);

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
      _apiCancelToken = CancelToken();
      final response = await _apiDio.get<List<dynamic>>(
        apiUrl,
        cancelToken: _apiCancelToken,
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

  // -----------------------------------------------------------------------
  // Internal — ZIP extraction
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

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Dio _defaultApiDio() => Dio(
  BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(minutes: 10),
    headers: {'User-Agent': appUserAgent},
  ),
);
