/// Unit tests for [WhisperServerManifest], its [WhisperServerManifestLoader]
/// failover chain, and the [WhisperBinarySelector] backend-priority logic.
library;

import 'dart:async';
import 'dart:convert' show jsonDecode;
import 'dart:io' show Directory, File, Platform;
import 'dart:typed_data' show Uint8List;

import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:whispaste/services/hardware_info_service.dart' as hw;
import 'package:whispaste/services/whisper_server_manifest.dart';

void main() {
  // ─────────────────────────────────────────────────────────────────────────
  // Parsing
  // ─────────────────────────────────────────────────────────────────────────

  group('WhisperServerManifest.fromJson', () {
    test('parses a well-formed manifest', () {
      final manifest = WhisperServerManifest.fromJson({
        'schema_version': 1,
        'whisper_server_tag': 'whisper-server-v1.8.4.1',
        'whisper_cpp_release': 'v1.8.4',
        'generated_at': '2026-05-27T00:00:00Z',
        'binaries': [
          {
            'platform': 'macos',
            'arch': 'arm64',
            'backend': 'metal',
            'url': 'https://example.com/metal.zip',
            'size_bytes': 1234567,
            'source': 'whispaste',
          },
        ],
      });

      expect(manifest.schemaVersion, 1);
      expect(manifest.whisperServerTag, 'whisper-server-v1.8.4.1');
      expect(manifest.whisperCppRelease, 'v1.8.4');
      expect(manifest.binaries, hasLength(1));
      expect(manifest.binaries.first.platform, 'macos');
      expect(manifest.binaries.first.sizeBytes, 1234567);
      expect(
        manifest.releaseAssetManifestUrl,
        'https://github.com/whispaste/whispaste/releases/download/'
        'whisper-server-v1.8.4.1/whisper-server-manifest.json',
      );
    });

    test('rejects an unsupported schema_version', () {
      expect(
        () => WhisperServerManifest.fromJson({
          'schema_version': 99,
          'whisper_server_tag': 'whisper-server-v1.8.4.1',
          'binaries': [
            {
              'platform': 'macos',
              'arch': 'arm64',
              'backend': 'metal',
              'url': 'https://example.com/metal.zip',
              'size_bytes': 1,
              'source': 'whispaste',
            },
          ],
        }),
        throwsA(isA<WhisperServerManifestException>()),
      );
    });

    test('rejects an empty binaries array', () {
      expect(
        () => WhisperServerManifest.fromJson({
          'schema_version': 1,
          'whisper_server_tag': 'whisper-server-v1.8.4.1',
          'binaries': <dynamic>[],
        }),
        throwsA(isA<WhisperServerManifestException>()),
      );
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Loader failover chain
  // ─────────────────────────────────────────────────────────────────────────

  group('WhisperServerManifestLoader.load()', () {
    test('returns the manifest from the raw URL when reachable, without '
        'falling through to the release-asset stage', () async {
      var rawHits = 0;
      var releaseHits = 0;

      final loader = WhisperServerManifestLoader(
        dio: _routedDio(
          onRaw: () {
            rawHits++;
            return _rawManifest;
          },
          onReleaseAsset: () {
            releaseHits++;
            return _releaseAssetManifest;
          },
        ),
        bundleReader: () async => _bundledManifest,
      );

      final manifest = await loader.load();

      expect(manifest.whisperServerTag, 'whisper-server-raw');
      expect(rawHits, 1);
      expect(releaseHits, 0);
    });

    test('falls back to the release-asset URL when the raw URL fails, using '
        'the tag from the bundled manifest to construct it', () async {
      var releaseHits = 0;

      final loader = WhisperServerManifestLoader(
        dio: _routedDio(
          onRaw: () => _connectionError(),
          onReleaseAsset: () {
            releaseHits++;
            return _releaseAssetManifest;
          },
        ),
        bundleReader: () async => _bundledManifest,
      );

      final manifest = await loader.load();
      expect(manifest.whisperServerTag, 'whisper-server-release');
      expect(releaseHits, 1);
    });

    test(
      'falls back to the bundled manifest when every remote source fails',
      () async {
        final loader = WhisperServerManifestLoader(
          dio: _routedDio(
            onRaw: () => _connectionError(),
            onReleaseAsset: () => _connectionError(),
          ),
          bundleReader: () async => _bundledManifest,
        );

        final manifest = await loader.load();
        expect(manifest.whisperServerTag, 'whisper-server-bundled');
      },
    );

    test('throws when bundle is missing AND both remote sources fail — the '
        'caller deserves a hard error instead of a silent null', () async {
      final loader = WhisperServerManifestLoader(
        dio: _routedDio(
          onRaw: () => _connectionError(),
          onReleaseAsset: () => _connectionError(),
        ),
        bundleReader: () async => throw Exception('no bundle in this build'),
      );

      await expectLater(
        () => loader.load(),
        throwsA(isA<WhisperServerManifestException>()),
      );
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Selector
  // ─────────────────────────────────────────────────────────────────────────

  group('WhisperBinarySelector.select', () {
    final manifest = WhisperServerManifest.fromJson({
      'schema_version': 1,
      'whisper_server_tag': 'whisper-server-test',
      'whisper_cpp_release': 'v1.8.4',
      'generated_at': '2026-01-01T00:00:00Z',
      'binaries': [
        _bin('macos', 'arm64', 'metal'),
        _bin('macos', 'arm64', 'cpu'),
        _bin('windows', 'x64', 'cuda12'),
        _bin('windows', 'x64', 'vulkan'),
        _bin('windows', 'x64', 'cpu'),
      ],
    });

    test('Apple Silicon → metal beats cpu', () {
      const selector = WhisperBinarySelector();
      final result = selector.select(
        manifest: manifest,
        gpu: const hw.GpuInfo(vendor: hw.GpuVendor.apple, name: 'Apple'),
        gpuMode: 'auto',
        platformOverride: 'macos',
        archOverride: 'arm64',
      );
      expect(result.hasBinary, isTrue);
      expect(result.binary!.backend, 'metal');
    });

    test('NVIDIA with CUDA → cuda12 beats vulkan', () {
      const selector = WhisperBinarySelector();
      final result = selector.select(
        manifest: manifest,
        gpu: const hw.GpuInfo(
          vendor: hw.GpuVendor.nvidia,
          name: 'NV',
          cudaAvailable: true,
        ),
        gpuMode: 'auto',
        platformOverride: 'windows',
        archOverride: 'x64',
      );
      expect(result.binary!.backend, 'cuda12');
    });

    test('NVIDIA without CUDA → vulkan beats cpu', () {
      const selector = WhisperBinarySelector();
      final result = selector.select(
        manifest: manifest,
        gpu: const hw.GpuInfo(vendor: hw.GpuVendor.nvidia, name: 'NV-no-cuda'),
        gpuMode: 'auto',
        platformOverride: 'windows',
        archOverride: 'x64',
      );
      expect(result.binary!.backend, 'vulkan');
    });

    test('AMD → vulkan', () {
      const selector = WhisperBinarySelector();
      final result = selector.select(
        manifest: manifest,
        gpu: const hw.GpuInfo(vendor: hw.GpuVendor.amd, name: 'AMD'),
        gpuMode: 'auto',
        platformOverride: 'windows',
        archOverride: 'x64',
      );
      expect(result.binary!.backend, 'vulkan');
    });

    test('gpuMode=disabled → cpu wins regardless of vendor', () {
      const selector = WhisperBinarySelector();
      final result = selector.select(
        manifest: manifest,
        gpu: const hw.GpuInfo(
          vendor: hw.GpuVendor.nvidia,
          name: 'NV',
          cudaAvailable: true,
        ),
        gpuMode: 'disabled',
        platformOverride: 'windows',
        archOverride: 'x64',
      );
      expect(result.binary!.backend, 'cpu');
    });

    test('Linux x64 with no binary in manifest → miss with reason', () {
      const selector = WhisperBinarySelector();
      final result = selector.select(
        manifest: manifest,
        gpu: const hw.GpuInfo(vendor: hw.GpuVendor.intel, name: 'Intel'),
        gpuMode: 'auto',
        platformOverride: 'linux',
        archOverride: 'x64',
      );
      expect(result.hasBinary, isFalse);
      expect(result.reason, contains('linux/x64'));
      expect(result.reason, contains('whisper-server-test'));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Linux binary selection (AC1 + AC2)
  // ─────────────────────────────────────────────────────────────────────────

  group('Linux binary selection', () {
    // Fixture manifest with Linux x64 and arm64 CPU entries.
    final linuxManifest = WhisperServerManifest.fromJson({
      'schema_version': 1,
      'whisper_server_tag': 'whisper-server-linux-test',
      'whisper_cpp_release': 'v1.8.4',
      'generated_at': '2026-01-01T00:00:00Z',
      'binaries': [
        _bin('linux', 'x64', 'cpu'),
        _bin('linux', 'arm64', 'cpu'),
        _bin('macos', 'arm64', 'metal'),
        _bin('windows', 'x64', 'cpu'),
      ],
    });

    test('linux/x64 CPU host selects linux/x64/cpu', () {
      const selector = WhisperBinarySelector();
      final result = selector.select(
        manifest: linuxManifest,
        gpu: const hw.GpuInfo(vendor: hw.GpuVendor.none, name: 'none'),
        gpuMode: 'auto',
        platformOverride: 'linux',
        archOverride: 'x64',
      );
      expect(result.hasBinary, isTrue);
      expect(result.binary!.platform, 'linux');
      expect(result.binary!.arch, 'x64');
      expect(result.binary!.backend, 'cpu');
    });

    test('linux/arm64 CPU host selects linux/arm64/cpu', () {
      const selector = WhisperBinarySelector();
      final result = selector.select(
        manifest: linuxManifest,
        gpu: const hw.GpuInfo(vendor: hw.GpuVendor.none, name: 'none'),
        gpuMode: 'auto',
        platformOverride: 'linux',
        archOverride: 'arm64',
      );
      expect(result.hasBinary, isTrue);
      expect(result.binary!.platform, 'linux');
      expect(result.binary!.arch, 'arm64');
      expect(result.binary!.backend, 'cpu');
    });

    test('linux/arm64 host → clean miss when manifest has no arm64 entry', () {
      final x64OnlyManifest = WhisperServerManifest.fromJson({
        'schema_version': 1,
        'whisper_server_tag': 'whisper-server-x64-only',
        'whisper_cpp_release': 'v1',
        'generated_at': '2026-01-01T00:00:00Z',
        'binaries': [_bin('linux', 'x64', 'cpu')],
      });
      const selector = WhisperBinarySelector();
      final result = selector.select(
        manifest: x64OnlyManifest,
        gpu: const hw.GpuInfo(vendor: hw.GpuVendor.none, name: 'none'),
        gpuMode: 'auto',
        platformOverride: 'linux',
        archOverride: 'arm64',
      );
      expect(result.hasBinary, isFalse);
      expect(result.reason, isNotNull);
      expect(result.reason, contains('linux/arm64'));
      expect(result.reason, contains('whisper-server-x64-only'));
    });

    // AC1 — verify that _hostArch() uses the real host arch (no archOverride).
    // On macOS the result must be arm64 (macOS behaviour unchanged).
    test(
      '_hostArch() returns arm64 on macOS (macOS behaviour unchanged)',
      () {
        final multiArchManifest = WhisperServerManifest.fromJson({
          'schema_version': 1,
          'whisper_server_tag': 'test',
          'whisper_cpp_release': 'v1',
          'generated_at': '2026-01-01T00:00:00Z',
          'binaries': [
            _bin('macos', 'arm64', 'metal'),
            _bin('macos', 'x64', 'metal'),
          ],
        });
        const selector = WhisperBinarySelector();
        // platformOverride fixes the platform; archOverride is omitted so
        // _hostArch() is exercised.
        final result = selector.select(
          manifest: multiArchManifest,
          gpu: const hw.GpuInfo(vendor: hw.GpuVendor.apple, name: 'Apple'),
          gpuMode: 'auto',
          platformOverride: 'macos',
        );
        expect(result.hasBinary, isTrue);
        expect(
          result.binary!.arch,
          'arm64',
          reason: 'macOS host should always resolve to arm64',
        );
      },
      skip: Platform.isMacOS ? null : 'macOS-only arch verification',
    );
  });

  // ─────────────────────────────────────────────────────────────────────────
  // SHA-256 field: backward compatibility + model parsing
  // ─────────────────────────────────────────────────────────────────────────

  group('WhisperBinary sha256 field', () {
    test('parses sha256 when present in JSON', () {
      const hex =
          'aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899';
      final binary = WhisperBinary.fromJson({
        'platform': 'macos',
        'arch': 'arm64',
        'backend': 'metal',
        'url': 'https://example.com/metal.zip',
        'size_bytes': 1000,
        'source': 'whispaste',
        'sha256': hex,
      });
      expect(binary.sha256, hex);
    });

    test(
      'sha256 is null when field is absent (legacy manifest — backward-compatible)',
      () {
        final binary = WhisperBinary.fromJson({
          'platform': 'macos',
          'arch': 'arm64',
          'backend': 'metal',
          'url': 'https://example.com/metal.zip',
          'size_bytes': 1000,
          'source': 'whispaste',
          // no sha256 key
        });
        expect(binary.sha256, isNull);
      },
    );

    test('manifest without any sha256 fields still parses successfully', () {
      final manifest = WhisperServerManifest.fromJson({
        'schema_version': 1,
        'whisper_server_tag': 'whisper-server-legacy',
        'whisper_cpp_release': 'v1',
        'generated_at': '2026-01-01T00:00:00Z',
        'binaries': [
          {
            'platform': 'macos',
            'arch': 'arm64',
            'backend': 'metal',
            'url': 'https://example.com/metal.zip',
            'size_bytes': 1000,
            'source': 'whispaste',
          },
        ],
      });
      expect(manifest.binaries.first.sha256, isNull);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // verifyFileSha256 integrity helper
  // ─────────────────────────────────────────────────────────────────────────

  group('verifyFileSha256', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('wp_sha256_test_');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('accepts a file whose digest matches the expected hex', () async {
      final data = Uint8List.fromList([1, 2, 3, 4, 5]);
      final expected = crypto.sha256.convert(data).toString();
      final file = File('${tempDir.path}/ok.zip')..writeAsBytesSync(data);

      // Must not throw.
      await expectLater(verifyFileSha256(file, expected), completes);
    });

    test('throws WhisperBinaryIntegrityException on digest mismatch', () async {
      final data = Uint8List.fromList([1, 2, 3, 4, 5]);
      final file = File('${tempDir.path}/bad.zip')..writeAsBytesSync(data);
      const wrongHex =
          '0000000000000000000000000000000000000000000000000000000000000000';

      await expectLater(
        () => verifyFileSha256(file, wrongHex),
        throwsA(isA<WhisperBinaryIntegrityException>()),
      );
    });

    test('is case-insensitive — upper-case expected hex is accepted', () async {
      final data = Uint8List.fromList([10, 20, 30]);
      final expectedLower = crypto.sha256.convert(data).toString();
      final expectedUpper = expectedLower.toUpperCase();
      final file = File('${tempDir.path}/case.zip')..writeAsBytesSync(data);

      await expectLater(verifyFileSha256(file, expectedUpper), completes);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // computeSha256Hex helper
  // ─────────────────────────────────────────────────────────────────────────

  group('computeSha256Hex', () {
    test('returns the correct hex digest', () {
      final data = Uint8List.fromList([0xde, 0xad, 0xbe, 0xef]);
      final expected = crypto.sha256.convert(data).toString();
      expect(computeSha256Hex(data), expected);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Log-level contracts (AC1 / AC2)
  //
  // The failover chain (raw → release-asset → bundled) is the *expected*
  // operating mode; per-stage failures must therefore log at INFO so that
  // normal operation produces no WARNING noise.  Only truly anomalous
  // conditions (e.g. missing bundled manifest in a shipping build) stay at
  // WARNING.
  // ─────────────────────────────────────────────────────────────────────────

  group('WhisperServerManifestLoader log levels', () {
    late List<LogRecord> captured;
    late StreamSubscription<LogRecord> sub;

    setUp(() {
      captured = [];
      Logger.root.level = Level.ALL;
      sub = Logger.root.onRecord.listen(captured.add);
    });

    tearDown(() async {
      await sub.cancel();
      captured.clear();
    });

    Iterable<LogRecord> manifestLogs() =>
        captured.where((r) => r.loggerName == 'WhisperServerManifest');

    // AC1 — per-stage DioException is INFO, cause retained in message.
    test('AC1: per-stage remote fetch failure (DioException) is logged at '
        'INFO, not WARNING; concrete cause is in the message', () async {
      final loader = WhisperServerManifestLoader(
        dio: _routedDio(
          onRaw: () => _connectionError(),
          onReleaseAsset: () => _releaseAssetManifest,
        ),
        bundleReader: () async => _bundledManifest,
      );

      await loader.load();

      final warnings = manifestLogs()
          .where((r) => r.level >= Level.WARNING)
          .toList();
      expect(
        warnings,
        isEmpty,
        reason:
            'Per-stage fetch failure is an expected fallback — must log at INFO',
      );

      // The failure cause must appear in at least one INFO log.
      final infoWithCause = manifestLogs()
          .where(
            (r) =>
                r.level == Level.INFO &&
                r.message.contains('raw') &&
                r.message.contains('fetch failed'),
          )
          .toList();
      expect(
        infoWithCause,
        isNotEmpty,
        reason:
            'Failure cause (source label + error) must appear in the INFO log',
      );
    });

    // AC1 — both remotes fail + bundled used: no WARNING, bundled path logged.
    test('AC1: both-remotes-fail + bundled-used → no WARNING, '
        'INFO log confirms bundled fallback', () async {
      final loader = WhisperServerManifestLoader(
        dio: _routedDio(
          onRaw: () => _connectionError(),
          onReleaseAsset: () => _connectionError(),
        ),
        bundleReader: () async => _bundledManifest,
      );

      final manifest = await loader.load();
      expect(manifest.whisperServerTag, 'whisper-server-bundled');

      final warnings = manifestLogs()
          .where((r) => r.level >= Level.WARNING)
          .toList();
      expect(
        warnings,
        isEmpty,
        reason:
            'Using the bundled manifest is the expected successful fallback — '
            'must not emit WARNING',
      );

      final bundledLog = manifestLogs()
          .where((r) => r.level == Level.INFO && r.message.contains('bundled'))
          .toList();
      expect(
        bundledLog,
        isNotEmpty,
        reason: 'INFO log should confirm the bundled fallback was used',
      );
    });

    // AC2 — bundle anomaly (missing in shipping build) still logs at WARNING;
    // remote fetch failures remain INFO even in the all-sources-fail path.
    test('AC2: bundle-missing + all-remotes-fail → loader throws, '
        'bundle-unreadable anomaly logged at WARNING, '
        'remote failures stay at INFO', () async {
      final loader = WhisperServerManifestLoader(
        dio: _routedDio(
          onRaw: () => _connectionError(),
          onReleaseAsset: () => _connectionError(),
        ),
        bundleReader: () async => throw Exception('no bundle'),
      );

      await expectLater(
        () => loader.load(),
        throwsA(isA<WhisperServerManifestException>()),
      );

      // The bundle-unreadable anomaly must still be logged at WARNING.
      final bundleWarning = manifestLogs()
          .where(
            (r) =>
                r.level >= Level.WARNING &&
                r.message.contains('Bundled manifest unreadable'),
          )
          .toList();
      expect(
        bundleWarning,
        isNotEmpty,
        reason:
            'Bundle unreadable is an anomalous build state — must log at WARNING',
      );

      // Remote-fetch failures must NOT produce additional WARNINGs.
      final remoteWarnings = manifestLogs()
          .where(
            (r) =>
                r.level >= Level.WARNING &&
                (r.message.contains('raw') ||
                    r.message.contains('release-asset')),
          )
          .toList();
      expect(
        remoteWarnings,
        isEmpty,
        reason:
            'Remote fetch failures are INFO even in the all-sources-fail path',
      );
    });
  });
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

Map<String, dynamic> _bin(String platform, String arch, String backend) => {
  'platform': platform,
  'arch': arch,
  'backend': backend,
  'url': 'https://example.com/$platform-$arch-$backend.zip',
  'size_bytes': 1000,
  'source': 'test',
};

const String _rawManifest =
    '{"schema_version":1,"whisper_server_tag":"whisper-server-raw",'
    '"whisper_cpp_release":"v1","generated_at":"2026-01-01T00:00:00Z",'
    '"binaries":[{"platform":"macos","arch":"arm64","backend":"metal",'
    '"url":"http://example.com/raw.zip","size_bytes":1,"source":"raw"}]}';

const String _releaseAssetManifest =
    '{"schema_version":1,"whisper_server_tag":"whisper-server-release",'
    '"whisper_cpp_release":"v1","generated_at":"2026-01-01T00:00:00Z",'
    '"binaries":[{"platform":"macos","arch":"arm64","backend":"metal",'
    '"url":"http://example.com/release.zip","size_bytes":1,"source":"release"}]}';

const String _bundledManifest =
    '{"schema_version":1,"whisper_server_tag":"whisper-server-bundled",'
    '"whisper_cpp_release":"v1","generated_at":"2026-01-01T00:00:00Z",'
    '"binaries":[{"platform":"macos","arch":"arm64","backend":"metal",'
    '"url":"http://example.com/bundled.zip","size_bytes":1,"source":"bundled"}]}';

// ---------------------------------------------------------------------------
// Test-only Dio routing helpers
// ---------------------------------------------------------------------------

/// Routes a Dio request to one of two responder closures based on
/// whether the path looks like a raw GitHub URL or a release-asset URL.
/// Each responder can return a JSON string (resolved as 200) or a
/// [DioException] (rejected).
Dio _routedDio({
  required Object Function() onRaw,
  required Object Function() onReleaseAsset,
}) {
  return Dio()
    ..interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final isRaw = options.path.contains('raw.githubusercontent.com');
          final isRelease = options.path.contains('/releases/download/');
          final responder = isRaw
              ? onRaw
              : isRelease
              ? onReleaseAsset
              : null;
          if (responder == null) {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.unknown,
                error: 'unrouted URL: ${options.path}',
              ),
            );
            return;
          }
          final result = responder();
          if (result is DioException) {
            handler.reject(result.copyWith(requestOptions: options));
            return;
          }
          if (result is String) {
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: jsonDecode(result) as Map<String, dynamic>,
              ),
            );
            return;
          }
          handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.unknown,
              error: 'unexpected responder return type: ${result.runtimeType}',
            ),
          );
        },
      ),
    );
}

DioException _connectionError() {
  return DioException(
    requestOptions: RequestOptions(path: ''),
    type: DioExceptionType.connectionError,
    error: 'offline test',
  );
}
