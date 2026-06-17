/// Whisper-server binary manifest — single source of truth for which
/// prebuilt server binaries are available for which platform / arch /
/// GPU backend.
///
/// The manifest is hosted in three places, queried in this order:
///
/// 1. `raw.githubusercontent.com/whispaste/whispaste/main/assets/whisper-server-manifest.json`
///    — atomically updated by the `build-whisper-server.yml` CI workflow.
///    CDN-cached, no GitHub-API rate limit involved.
/// 2. `github.com/whispaste/whispaste/releases/download/<tag>/whisper-server-manifest.json`
///    — same file, uploaded as an asset on the matching server release.
///    Independent CDN path; protects against narrow raw-host outages.
/// 3. The asset bundled with the app
///    (`assets/whisper-server-manifest.json`) — frozen at app build
///    time, guarantees the onboarding completes even when both remote
///    sources are unreachable.
///
/// The bundled copy is also the source of the tag used to construct
/// the stage-2 URL — installed apps can therefore find the manifest
/// even if GitHub's raw host is down, as long as the originally-pinned
/// release still exists.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:sentry_dio/sentry_dio.dart';

import '../core/app_info.dart';
import '../core/logging/app_logger.dart';
import 'hardware_info_service.dart' as hw;
import 'http_model_fetcher.dart';

final _log = AppLogger('WhisperServerManifest');

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// Schema version of the manifest format this build understands.
const int _supportedSchemaVersion = 1;

/// Bundled asset path. Must match the `assets:` entry in `pubspec.yaml`.
const String _bundledAssetPath = 'assets/whisper-server-manifest.json';

/// Primary remote URL (raw GitHub content, CDN-cached, no rate limit).
const String _primaryRemoteUrl =
    'https://raw.githubusercontent.com/whispaste/whispaste/main/assets/whisper-server-manifest.json';

/// Per-request timeout for each remote attempt — kept short so a stuck
/// network does not block the onboarding for more than a few seconds.
const Duration _remoteTimeout = Duration(seconds: 6);

// ---------------------------------------------------------------------------
// Domain types
// ---------------------------------------------------------------------------

/// One downloadable whisper-server binary variant.
class WhisperBinary {
  const WhisperBinary({
    required this.platform,
    required this.arch,
    required this.backend,
    required this.url,
    required this.sizeBytes,
    required this.source,
    this.sha256,
  });

  /// `macos`, `windows`, `linux`.
  final String platform;

  /// `arm64`, `x64`.
  final String arch;

  /// `metal`, `vulkan`, `cuda12`, `cpu`.
  final String backend;

  /// Direct download URL of the ZIP archive.
  final String url;

  /// Archive size in bytes. Used for progress estimation.
  final int sizeBytes;

  /// `whispaste` (built by build-whisper-server.yml) or `upstream`
  /// (taken straight from a ggml-org/whisper.cpp release).
  final String source;

  /// Optional SHA-256 hex digest of the ZIP archive. When present the
  /// downloader verifies the downloaded artefact before extraction.
  /// Absent in legacy manifests — treated as "no verification" (backward-
  /// compatible).
  final String? sha256;

  factory WhisperBinary.fromJson(Map<String, dynamic> json) {
    return WhisperBinary(
      platform: json['platform'] as String,
      arch: json['arch'] as String,
      backend: json['backend'] as String,
      url: json['url'] as String,
      sizeBytes: (json['size_bytes'] as num).toInt(),
      source: json['source'] as String? ?? 'unknown',
      sha256: json['sha256'] as String?,
    );
  }

  @override
  String toString() =>
      'WhisperBinary($platform/$arch/$backend, ${sizeBytes ~/ (1024 * 1024)}MB, $source)';
}

// ---------------------------------------------------------------------------
// SHA-256 integrity helpers
// ---------------------------------------------------------------------------

/// Thrown when the SHA-256 digest of a downloaded artefact does not match
/// the value recorded in the manifest.
class WhisperBinaryIntegrityException implements Exception {
  const WhisperBinaryIntegrityException({
    required this.expected,
    required this.actual,
    required this.path,
  });

  final String expected;
  final String actual;
  final String path;

  @override
  String toString() =>
      'WhisperBinaryIntegrityException: SHA-256 mismatch for $path '
      '(expected=$expected, actual=$actual)';
}

/// Verifies [file] against [expectedHex].
///
/// Throws [WhisperBinaryIntegrityException] on mismatch.
/// Returns normally when the digests match.
Future<void> verifyFileSha256(File file, String expectedHex) async {
  final bytes = await file.readAsBytes();
  final actual = sha256.convert(bytes).toString();
  if (actual != expectedHex.toLowerCase()) {
    throw WhisperBinaryIntegrityException(
      expected: expectedHex.toLowerCase(),
      actual: actual,
      path: file.path,
    );
  }
}

/// Computes the SHA-256 hex digest of [data].
String computeSha256Hex(Uint8List data) => sha256.convert(data).toString();

/// Parsed manifest. Immutable.
class WhisperServerManifest {
  const WhisperServerManifest({
    required this.schemaVersion,
    required this.whisperServerTag,
    required this.whisperCppRelease,
    required this.binaries,
  });

  final int schemaVersion;
  final String whisperServerTag;
  final String whisperCppRelease;
  final List<WhisperBinary> binaries;

  factory WhisperServerManifest.fromJson(Map<String, dynamic> json) {
    final schema = (json['schema_version'] as num?)?.toInt() ?? 0;
    if (schema > _supportedSchemaVersion) {
      throw WhisperServerManifestException(
        'Unsupported manifest schema_version=$schema '
        '(this build supports up to $_supportedSchemaVersion)',
      );
    }
    final binariesJson = json['binaries'] as List<dynamic>?;
    if (binariesJson == null || binariesJson.isEmpty) {
      throw const WhisperServerManifestException(
        'Manifest has no `binaries` array',
      );
    }
    return WhisperServerManifest(
      schemaVersion: schema,
      whisperServerTag: json['whisper_server_tag'] as String,
      whisperCppRelease: json['whisper_cpp_release'] as String? ?? 'unknown',
      binaries: [
        for (final b in binariesJson)
          WhisperBinary.fromJson(b as Map<String, dynamic>),
      ],
    );
  }

  /// URL to query for the matching release-asset copy of this manifest
  /// (the stage-2 failover endpoint). Derived from the manifest's own
  /// tag so an installed app can always self-bootstrap from its bundled
  /// copy.
  String get releaseAssetManifestUrl =>
      'https://github.com/whispaste/whispaste/releases/download/'
      '$whisperServerTag/whisper-server-manifest.json';
}

/// Thrown when manifest parsing / validation fails.
class WhisperServerManifestException implements Exception {
  const WhisperServerManifestException(this.message);
  final String message;
  @override
  String toString() => 'WhisperServerManifestException: $message';
}

// ---------------------------------------------------------------------------
// Loader
// ---------------------------------------------------------------------------

/// Reads the raw JSON string of the bundled manifest. Indirected so
/// tests can inject a fixture without touching Flutter's asset system.
typedef ManifestBundleReader = Future<String> Function();

Future<String> _defaultBundleReader() =>
    rootBundle.loadString(_bundledAssetPath);

/// Three-tier loader: raw URL → release-asset URL → bundled fallback.
class WhisperServerManifestLoader {
  WhisperServerManifestLoader({Dio? dio, ManifestBundleReader? bundleReader})
    : _dio = dio ?? _defaultDio(),
      _bundleReader = bundleReader ?? _defaultBundleReader;

  final Dio _dio;
  final ManifestBundleReader _bundleReader;

  /// Loads the manifest, walking the failover chain. Always returns a
  /// usable manifest (the bundled one if every remote source fails) —
  /// the caller never has to handle a null.
  Future<WhisperServerManifest> load() async {
    // Bundled copy is read up front: it both (a) supplies the tag we
    // need to construct the stage-2 URL and (b) acts as the final
    // fallback if both remote attempts fail. Reading it is essentially
    // free (single asset lookup).
    WhisperServerManifest? bundled;
    try {
      bundled = await _loadFromBundle();
    } on Exception catch (e) {
      // No bundled copy at all is unrecoverable — every shipping build
      // includes one. Re-throw so the caller sees a hard error rather
      // than a silent string-of-failures.
      _log.warning('Bundled manifest unreadable: $e');
      // We still try remote sources first — they might rescue us.
    }

    // Stage 1: raw URL.
    final fromRaw = await _tryFetch(_primaryRemoteUrl, label: 'raw');
    if (fromRaw != null) return fromRaw;

    // Stage 2: release-asset URL derived from the bundled tag.
    if (bundled != null) {
      final fromRelease = await _tryFetch(
        bundled.releaseAssetManifestUrl,
        label: 'release-asset',
      );
      if (fromRelease != null) return fromRelease;
    }

    // Stage 3: bundled fallback.
    if (bundled != null) {
      _log.info(
        'Both remote manifest sources unreachable — using bundled copy '
        '(tag=${bundled.whisperServerTag})',
      );
      return bundled;
    }

    throw const WhisperServerManifestException(
      'Manifest unreadable from all sources (raw, release-asset, bundle)',
    );
  }

  /// Single fetch attempt. Returns `null` on any failure so the caller
  /// can proceed to the next stage. Errors are logged for diagnostics
  /// but never thrown.
  ///
  /// Failures are logged at INFO — walking a multi-stage failover chain is
  /// the expected behaviour, not an error condition.  The concrete cause
  /// (status code, network error) is preserved in the message so the log
  /// is still useful for diagnosing persistent connectivity problems.
  Future<WhisperServerManifest?> _tryFetch(
    String url, {
    required String label,
  }) async {
    try {
      // GitHub serves JSON manifests as text/plain (raw host) or
      // application/octet-stream (release assets). Dio's ResponseType.json
      // leaves the body as a String for those content-types and the
      // `<Map<String, dynamic>>` cast then fails with DioExceptionType.unknown
      // ("Netzwerkfehler: unknown"). Fetch as plain text and parse ourselves.
      final response = await _dio.get<String>(
        url,
        options: Options(
          responseType: ResponseType.plain,
          sendTimeout: _remoteTimeout,
          receiveTimeout: _remoteTimeout,
        ),
      );
      final body = response.data;
      if (body == null || body.isEmpty) {
        _log.info('Manifest $label returned empty body ($url)');
        return null;
      }
      final manifest = WhisperServerManifest.fromJson(_parseJson(body));
      _log.info(
        'Loaded manifest from $label (tag=${manifest.whisperServerTag}, '
        'binaries=${manifest.binaries.length})',
      );
      return manifest;
    } on DioException catch (e) {
      _log.info('Manifest $label fetch failed: ${describeDioError(e)}');
      return null;
    } on WhisperServerManifestException catch (e) {
      _log.info('Manifest $label parse failed: ${e.message}');
      return null;
    } on Exception catch (e) {
      _log.info('Manifest $label unexpected error: $e');
      return null;
    }
  }

  Future<WhisperServerManifest> _loadFromBundle() async {
    final raw = await _bundleReader();
    final data = _parseJson(raw);
    return WhisperServerManifest.fromJson(data);
  }
}

// ---------------------------------------------------------------------------
// Selector
// ---------------------------------------------------------------------------

/// Result of a selector lookup. Either a [binary] is provided or
/// [reason] explains why no binary matched (used for diagnostics and
/// the error message shown to the user).
class WhisperBinarySelection {
  const WhisperBinarySelection.match(this.binary) : reason = null;
  const WhisperBinarySelection.miss(this.reason) : binary = null;

  final WhisperBinary? binary;
  final String? reason;

  bool get hasBinary => binary != null;
}

/// Deterministic platform/arch/GPU → binary lookup against a manifest.
///
/// Encodes the same backend priorities the legacy pattern matcher used,
/// but as an explicit list instead of asset-name substrings:
///
/// | vendor / cuda / mode | backend priority           |
/// |----------------------|----------------------------|
/// | gpu mode = disabled  | cpu                        |
/// | nvidia + cuda12      | cuda12, vulkan, cpu        |
/// | nvidia (Kepler/none) | vulkan, cpu                |
/// | amd / intel          | vulkan, cpu                |
/// | apple                | metal, cpu                 |
/// | none                 | cpu                        |
class WhisperBinarySelector {
  const WhisperBinarySelector();

  /// Picks the best-matching binary, or returns a [WhisperBinarySelection.miss]
  /// with a diagnostic [reason] when nothing fits.
  WhisperBinarySelection select({
    required WhisperServerManifest manifest,
    required hw.GpuInfo gpu,
    required String gpuMode,
    String? platformOverride,
    String? archOverride,
  }) {
    final platform = platformOverride ?? _hostPlatform();
    final arch = archOverride ?? _hostArch();
    final priority = _backendPriority(
      vendor: gpu.vendor,
      cuda12Capable: gpu.supportsCuda12,
      gpuMode: gpuMode,
    );

    for (final backend in priority) {
      for (final binary in manifest.binaries) {
        if (binary.platform == platform &&
            binary.arch == arch &&
            binary.backend == backend &&
            _isDownloadable(binary)) {
          return WhisperBinarySelection.match(binary);
        }
      }
    }

    final available = manifest.binaries
        .where((b) => b.platform == platform && b.arch == arch)
        .map((b) => b.backend)
        .toList();
    return WhisperBinarySelection.miss(
      'No whisper-server binary for $platform/$arch matches backend '
      'priorities $priority (manifest provides: $available, '
      'manifest tag=${manifest.whisperServerTag})',
    );
  }

  /// Whether [binary] has a non-empty http(s) URL the downloader can fetch.
  static bool _isDownloadable(WhisperBinary binary) {
    final url = binary.url.trim();
    return url.startsWith('http://') || url.startsWith('https://');
  }

  /// Backend priority list — first match wins. Same precedence rules as
  /// the legacy `serverAssetPatterns` helper.
  static List<String> _backendPriority({
    required hw.GpuVendor vendor,
    required bool cuda12Capable,
    required String gpuMode,
  }) {
    if (gpuMode == 'disabled') return const ['cpu'];
    switch (vendor) {
      case hw.GpuVendor.nvidia:
        // `cuda12Capable` (from `GpuInfo.supportsCuda12`), not raw CUDA
        // availability: a Kepler/Fermi NVIDIA card has CUDA but cannot run the
        // cuda12 binary, so it must fall straight to the Vulkan variant.
        return cuda12Capable
            ? const ['cuda12', 'vulkan', 'cpu']
            : const ['vulkan', 'cpu'];
      case hw.GpuVendor.amd:
      case hw.GpuVendor.intel:
        return const ['vulkan', 'cpu'];
      case hw.GpuVendor.apple:
        return const ['metal', 'cpu'];
      case hw.GpuVendor.none:
        return const ['cpu'];
    }
  }

  static String _hostPlatform() {
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    return Platform.operatingSystem;
  }

  static String _hostArch() {
    // macOS ships arm64-only (Intel Mac support was dropped).
    if (Platform.isMacOS) return 'arm64';
    // Use dart:ffi Abi to detect the real CPU architecture so arm64 Linux
    // hosts receive the correct binary instead of the hard-coded x64 fallback.
    final abi = Abi.current();
    if (abi == Abi.linuxArm64 || abi == Abi.windowsArm64) return 'arm64';
    return 'x64';
  }
}

Map<String, dynamic> _parseJson(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is! Map<String, dynamic>) {
    throw const WhisperServerManifestException(
      'Manifest JSON root must be an object',
    );
  }
  return decoded;
}

Dio _defaultDio() {
  final dio = Dio(
    BaseOptions(
      connectTimeout: _remoteTimeout,
      receiveTimeout: _remoteTimeout,
      headers: {'User-Agent': appUserAgent},
    ),
  );
  // `captureFailedRequests: false`: the loader deliberately walks a failover
  // chain (raw → release-asset → bundled), swallowing each stage's failure in
  // `_tryFetch` and moving on. Letting `addSentry()`'s interceptor auto-capture
  // those intermediate 5xx (default range 500–599) would emit a Sentry event
  // for an expected, fully-handled condition — the same zero-value noise the
  // update-check client avoids. Tracing spans + breadcrumbs stay on.
  dio.addSentry(captureFailedRequests: false);
  return dio;
}
