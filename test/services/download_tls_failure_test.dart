import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/download_tls_failure.dart';

void main() {
  final options = RequestOptions(path: 'https://huggingface.co/');

  test('handshake failure with CERTIFICATE_VERIFY_FAILED is a TLS failure', () {
    final e = DioException.connectionError(
      requestOptions: options,
      reason: 'Handshake error',
      error: const HandshakeException(
        'Handshake error in client (OS Error: CERTIFICATE_VERIFY_FAILED: '
        'unable to get local issuer certificate)',
      ),
    );

    expect(isTlsDownloadFailure(e), isTrue);
  });

  test('a TLS error reported only in the message is a TLS failure', () {
    final e = DioException(
      requestOptions: options,
      message: 'CERTIFICATE_VERIFY_FAILED',
    );

    expect(isTlsDownloadFailure(e), isTrue);
  });

  test('a plain network error is not a TLS failure', () {
    final e = DioException.connectionError(
      requestOptions: options,
      reason: 'Connection refused',
      error: const SocketException('Connection refused'),
    );

    expect(isTlsDownloadFailure(e), isFalse);
  });

  test('a cancelled download is not a TLS failure', () {
    final e = DioException(
      requestOptions: options,
      type: DioExceptionType.cancel,
    );

    expect(isTlsDownloadFailure(e), isFalse);
  });
}
