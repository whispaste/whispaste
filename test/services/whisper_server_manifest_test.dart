/// Unit tests for [WhisperServerManifest], its [WhisperServerManifestLoader]
/// failover chain, and the [WhisperBinarySelector] backend-priority logic.
library;

import 'dart:convert' show jsonDecode;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

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
