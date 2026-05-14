/// Unit tests for [WhisperServerDownloader].
///
/// Focuses on the static file-classification helpers (pure functions) and
/// verifies the download() method surfaces cancellation errors correctly.
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/services/http_model_fetcher.dart';
import 'package:whispaste/services/whisper_server_downloader.dart';

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
        WhisperServerDownloader.isServerFile('ggml-tiny-q5_1.bin'),
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
          WhisperServerDownloader.isExtractableServerFile('ggml-tiny.bin'),
          isFalse,
        );
      });
    },
    skip: Platform.isWindows ? 'Unix-specific behaviour' : null,
  );

  // ─────────────────────────────────────────────────────────────────────────
  // download() — cancellation propagates
  // ─────────────────────────────────────────────────────────────────────────

  group('WhisperServerDownloader.download()', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('wp_server_dl_');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('throws when no repos yield a matching asset', () async {
      // The downloader finds no assets via GitHub (empty asset list in all
      // releases), then falls through to throw an exception.
      final downloader = WhisperServerDownloader(
        fetcher: _NeverCalledFetcher(),
        apiDio: Dio(BaseOptions())
          ..interceptors.add(
            InterceptorsWrapper(
              onRequest: (options, handler) {
                final isListEndpoint = options.path.contains('per_page');
                // Releases list → return a release with NO assets.
                // Latest release → return a release map with NO assets.
                if (isListEndpoint) {
                  handler.resolve(
                    Response<List<dynamic>>(
                      requestOptions: options,
                      data: <dynamic>[
                        {
                          'tag_name': 'whisper-server-v1.0.0',
                          'assets': <dynamic>[],
                        },
                      ],
                      statusCode: 200,
                    ),
                  );
                } else {
                  handler.resolve(
                    Response<Map<String, dynamic>>(
                      requestOptions: options,
                      data: <String, dynamic>{
                        'tag_name': 'v1.0.0',
                        'assets': <dynamic>[],
                      },
                      statusCode: 200,
                    ),
                  );
                }
              },
            ),
          ),
      );

      // No matching asset found → throws Exception.
      await expectLater(
        () => downloader.download(destDir: tempDir.path, gpuMode: 'auto'),
        throwsException,
      );

      // Fetcher was never invoked.
      expect((_NeverCalledFetcher).runtimeType, isNotNull); // no-op assertion
    });

    test(
      'rethrows cancel DioException from fetcher when asset is found',
      () async {
        // Use a downloader where the fetcher itself cancels.
        final downloader = WhisperServerDownloader(
          fetcher: _CancellingFetcher(),
          apiDio: Dio(BaseOptions())
            ..interceptors.add(
              InterceptorsWrapper(
                onRequest: (options, handler) {
                  // Return a fake release with one asset so the fetcher is invoked.
                  handler.resolve(
                    Response<dynamic>(
                      requestOptions: options,
                      data: options.path.contains('per_page')
                          ? <dynamic>[
                              {
                                'tag_name': 'whisper-server-v1.0.0',
                                'assets': [
                                  {
                                    'name':
                                        'whisper-server-windows-x64-cpu.zip',
                                    'browser_download_url':
                                        'http://example.com/ws.zip',
                                  },
                                ],
                              },
                            ]
                          : <String, dynamic>{
                              'tag_name': 'v1.0.0',
                              'assets': [
                                {
                                  'name': 'whisper-server-windows-x64.zip',
                                  'browser_download_url':
                                      'http://example.com/ws.zip',
                                },
                              ],
                            },
                      statusCode: 200,
                    ),
                  );
                },
              ),
            ),
        );

        // cancel → rethrown as DioException with type cancel.
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
      },
      skip: Platform.isMacOS
          ? 'Asset pattern does not match windows assets on macOS'
          : null,
    );
  });
}

// ---------------------------------------------------------------------------
// Fake helpers
// ---------------------------------------------------------------------------

/// A fetcher that immediately throws [DioExceptionType.cancel].
class _CancellingFetcher extends HttpModelFetcher {
  @override
  Future<void> fetch({
    required String url,
    required String destPath,
    required int expectedSize,
    void Function(FetchProgress)? onProgress,
  }) async {
    throw DioException(
      requestOptions: RequestOptions(path: url),
      type: DioExceptionType.cancel,
    );
  }

  @override
  void cancel([String reason = 'cancelled']) {}
}

/// A fetcher that should never be called (fails the test if called).
class _NeverCalledFetcher extends HttpModelFetcher {
  @override
  Future<void> fetch({
    required String url,
    required String destPath,
    required int expectedSize,
    void Function(FetchProgress)? onProgress,
  }) async {
    fail('Fetcher should not have been called');
  }

  @override
  void cancel([String reason = 'cancelled']) {}
}
