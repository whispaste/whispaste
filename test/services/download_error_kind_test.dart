import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/download_error_kind.dart';

void main() {
  final request = RequestOptions(path: 'https://example.invalid/model.bin');

  group('classifyDownloadError (UIA-ONB-03)', () {
    test('a connection or HTTP failure is a network error', () {
      expect(
        classifyDownloadError(
          DioException(
            requestOptions: request,
            type: DioExceptionType.connectionError,
            error: const SocketException('Connection refused'),
          ),
        ),
        DownloadErrorKind.network,
      );
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
        classifyDownloadError(const SocketException('offline')),
        DownloadErrorKind.network,
      );
      expect(
        classifyDownloadError(TimeoutException('stalled')),
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
