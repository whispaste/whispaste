/// Unit tests for [WhisperServerDownloader].
///
/// The downloader's old GitHub-Releases-API path was replaced by the
/// manifest-driven architecture. These tests verify:
///
/// 1. Static file-classification helpers (pure functions).
/// 2. `download()` reaches the fetcher with the URL the selector picked.
/// 3. `download()` surfaces user cancellation as a [DioException].
/// 4. `download()` throws a descriptive [Exception] when the manifest
///    contains no binary for the host platform.
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/services/http_model_fetcher.dart';
import 'package:whispaste/services/whisper_server_downloader.dart';
import 'package:whispaste/services/whisper_server_manifest.dart';

void main() {
  // ─────────────────────────────────────────────────────────────────────────
  // Static classification helpers
  // ─────────────────────────────────────────────────────────────────────────

  group('WhisperServerDownloader.isServerFile', () {
    test('whisper-server binary names are recognised', () {
      expect(WhisperServerDownloader.isServerFile('whisper-server'), isTrue);
      expect(
        WhisperServerDownloader.isServerFile('whisper-server.exe'),
        isTrue,
      );
    });

    test('shared library extensions are recognised', () {
      expect(WhisperServerDownloader.isServerFile('libfoo.dll'), isTrue);
      expect(WhisperServerDownloader.isServerFile('libfoo.dylib'), isTrue);
      expect(WhisperServerDownloader.isServerFile('libfoo.so'), isTrue);
      expect(WhisperServerDownloader.isServerFile('default.metallib'), isTrue);
    });

    test('model / unrelated files are NOT matched', () {
      expect(
        WhisperServerDownloader.isServerFile('ggml-small-q5_1.bin'),
        isFalse,
      );
      expect(WhisperServerDownloader.isServerFile('README.txt'), isFalse);
      expect(
        WhisperServerDownloader.isServerFile('whisper-server.tmp'),
        isFalse,
      );
    });
  });

  group(
    'WhisperServerDownloader.isExtractableServerFile (non-Windows)',
    () {
      test('shared library extensions are extractable', () {
        expect(
          WhisperServerDownloader.isExtractableServerFile('libwhisper.dylib'),
          isTrue,
        );
        expect(
          WhisperServerDownloader.isExtractableServerFile('libwhisper.so'),
          isTrue,
        );
        expect(
          WhisperServerDownloader.isExtractableServerFile('default.metallib'),
          isTrue,
        );
      });

      test('extensionless files (binaries) are extractable', () {
        expect(
          WhisperServerDownloader.isExtractableServerFile('whisper-server'),
          isTrue,
        );
        expect(
          WhisperServerDownloader.isExtractableServerFile('server'),
          isTrue,
        );
      });

      test('dotted non-library files are NOT extracted', () {
        expect(
          WhisperServerDownloader.isExtractableServerFile('readme.txt'),
          isFalse,
        );
        expect(
          WhisperServerDownloader.isExtractableServerFile('ggml-small.bin'),
          isFalse,
        );
      });
    },
    skip: Platform.isWindows ? 'Unix-specific behaviour' : null,
  );

  // ─────────────────────────────────────────────────────────────────────────
  // download()
  // ─────────────────────────────────────────────────────────────────────────

  group('WhisperServerDownloader.download()', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('wp_server_dl_');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('selector picks the binary that matches the host platform and hands '
        'its URL to the fetcher', () async {
      final capturing = _CapturingFetcher();
      final downloader = WhisperServerDownloader(
        fetcher: capturing,
        manifestLoader: _fakeManifestLoader(),
      );

      // The fetcher records the URL and then throws cancel so the
      // download loop exits without trying real disk extraction.
      await expectLater(
        () => downloader.download(destDir: tempDir.path, gpuMode: 'auto'),
        throwsA(
          isA<DioException>().having(
            (e) => e.type,
            'type',
            DioExceptionType.cancel,
          ),
        ),
      );

      expect(capturing.lastUrl, isNotNull);
      // Any of the host-matching variants is acceptable — the exact
      // backend depends on the runner's GPU detection. What matters
      // is that we landed on a URL from the fake manifest.
      expect(
        capturing.lastUrl,
        startsWith('http://example.com/'),
        reason:
            'Fetcher should have been called with a URL from the fake manifest',
      );
    });

    test('throws a descriptive Exception when the manifest holds no binary '
        'for the host platform', () async {
      final downloader = WhisperServerDownloader(
        fetcher: _NeverCalledFetcher(),
        manifestLoader: _emptyManifestLoader(),
      );

      await expectLater(
        () => downloader.download(destDir: tempDir.path, gpuMode: 'auto'),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('No whisper-server binary'),
          ),
        ),
      );
    });
  });
}

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

/// Fetcher that records the URL it was called with and immediately
/// throws a user-style cancel so the download loop terminates without
/// touching the filesystem.
class _CapturingFetcher extends HttpModelFetcher {
  String? lastUrl;

  @override
  Future<void> fetch({
    required String url,
    required String destPath,
    required int expectedSize,
    void Function(FetchProgress)? onProgress,
  }) async {
    lastUrl = url;
    throw DioException(
      requestOptions: RequestOptions(path: url),
      type: DioExceptionType.cancel,
      message: 'cancelled',
    );
  }

  @override
  void cancel([String reason = 'cancelled']) {}
}

/// Fetcher that must never be invoked (used when the selector is
/// expected to short-circuit).
class _NeverCalledFetcher extends HttpModelFetcher {
  @override
  Future<void> fetch({
    required String url,
    required String destPath,
    required int expectedSize,
    void Function(FetchProgress)? onProgress,
  }) async {
    fail('Fetcher should not have been called (url=$url)');
  }

  @override
  void cancel([String reason = 'cancelled']) {}
}

/// Manifest loader backed by a fixture covering every host platform a
/// CI runner is likely to be. Skips the network entirely.
WhisperServerManifestLoader _fakeManifestLoader() {
  return WhisperServerManifestLoader(
    dio: _offlineDio(),
    bundleReader: () async => _crossPlatformManifestJson,
  );
}

WhisperServerManifestLoader _emptyManifestLoader() {
  const empty = '''
{
  "schema_version": 1,
  "whisper_server_tag": "whisper-server-empty",
  "whisper_cpp_release": "test",
  "generated_at": "2026-01-01T00:00:00Z",
  "binaries": [
    {"platform":"unknown","arch":"unknown","backend":"cpu","url":"http://example.com/none.zip","size_bytes":1,"source":"test"}
  ]
}
''';
  return WhisperServerManifestLoader(
    dio: _offlineDio(),
    bundleReader: () async => empty,
  );
}

Dio _offlineDio() {
  // Reject every remote call instantly so the loader falls through to
  // the bundled fixture without waiting on a real network timeout.
  return Dio()
    ..interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.connectionError,
              error: 'offline test',
            ),
          );
        },
      ),
    );
}

const String _crossPlatformManifestJson = '''
{
  "schema_version": 1,
  "whisper_server_tag": "whisper-server-test",
  "whisper_cpp_release": "test",
  "generated_at": "2026-01-01T00:00:00Z",
  "binaries": [
    {"platform":"macos","arch":"arm64","backend":"metal","url":"http://example.com/metal.zip","size_bytes":1000,"source":"whispaste"},
    {"platform":"macos","arch":"arm64","backend":"cpu","url":"http://example.com/cpu-mac.zip","size_bytes":1000,"source":"whispaste"},
    {"platform":"windows","arch":"x64","backend":"cuda12","url":"http://example.com/cuda.zip","size_bytes":1000,"source":"upstream"},
    {"platform":"windows","arch":"x64","backend":"vulkan","url":"http://example.com/vulkan.zip","size_bytes":1000,"source":"whispaste"},
    {"platform":"windows","arch":"x64","backend":"cpu","url":"http://example.com/cpu-win.zip","size_bytes":1000,"source":"upstream"},
    {"platform":"linux","arch":"x64","backend":"cpu","url":"http://example.com/cpu-linux.zip","size_bytes":1000,"source":"upstream"}
  ]
}
''';
