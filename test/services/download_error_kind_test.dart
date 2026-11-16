import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/download_error_kind.dart';

void main() {
  final request = RequestOptions(path: 'https://example.invalid/model.bin');

  group('classifyDownloadError (UIA-ONB-03)', () {
    test('no connection to the server is its own offline state (#235)', () {
      expect(
        classifyDownloadError(
          DioException(
            requestOptions: request,
            type: DioExceptionType.connectionError,
            error: const SocketException('Connection refused'),
          ),
        ),
        DownloadErrorKind.offline,
      );
      expect(
        classifyDownloadError(
          DioException.connectionError(
            requestOptions: request,
            reason: 'no route',
          ),
        ),
        DownloadErrorKind.offline,
      );
      expect(
        classifyDownloadError(
          DioException.connectionTimeout(
            requestOptions: request,
            timeout: const Duration(seconds: 30),
          ),
        ),
        DownloadErrorKind.offline,
      );
      expect(
        classifyDownloadError(const SocketException('offline')),
        DownloadErrorKind.offline,
      );
    });

    test('a certificate failure stays a TLS error, not offline', () {
      expect(
        classifyDownloadError(
          DioException(
            requestOptions: request,
            type: DioExceptionType.connectionError,
            error: const HandshakeException('CERTIFICATE_VERIFY_FAILED'),
          ),
        ),
        DownloadErrorKind.tls,
      );
    });

    test('a server or transfer failure is a network error', () {
      expect(
        classifyDownloadError(
          DioException.badResponse(
            statusCode: 503,
            requestOptions: request,
            response: Response(requestOptions: request, statusCode: 503),
          ),
        ),
        DownloadErrorKind.network,
      );
      expect(
        classifyDownloadError(TimeoutException('stalled')),
        DownloadErrorKind.network,
      );
      // A connection lost mid-transfer is no offline state: the device was
      // online a moment ago, and retrying helps.
      expect(
        classifyDownloadError(
          DioException(
            requestOptions: request,
            type: DioExceptionType.unknown,
            error: const SocketException('Connection reset by peer'),
          ),
        ),
        DownloadErrorKind.network,
      );
      expect(
        classifyDownloadError(
          DioException.receiveTimeout(
            requestOptions: request,
            timeout: const Duration(seconds: 30),
          ),
        ),
        DownloadErrorKind.network,
      );
    });

    test('a failed write is a storage error, also when Dio wraps it', () {
      const diskFull = FileSystemException(
        'Write failed',
        '/models/model.bin',
        OSError('No space left on device', 28),
      );
      expect(classifyDownloadError(diskFull), DownloadErrorKind.storage);
      expect(
        classifyDownloadError(
          DioException(
            requestOptions: request,
            type: DioExceptionType.unknown,
            error: diskFull,
          ),
        ),
        DownloadErrorKind.storage,
      );
    });

    test('anything else is unknown', () {
      expect(
        classifyDownloadError(StateError('boom')),
        DownloadErrorKind.unknown,
      );
    });
  });
}
