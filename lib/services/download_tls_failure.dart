import 'dart:io';

import 'package:dio/dio.dart';

/// Error code stored in a download's `errorMessage` for TLS and certificate
/// failures. The UI maps it to `l10n.downloadTlsError`; the raw TLS text goes
/// to the local log only.
const String downloadTlsErrorCode = 'download_tls_error';

/// True if [e] is a TLS handshake or certificate-trust failure, e.g.
/// `HandshakeException: ... CERTIFICATE_VERIFY_FAILED`. Dio reports these as
/// `DioException.connectionError` with the `HandshakeException` in `error`.
bool isTlsDownloadFailure(DioException e) =>
    _isTlsError(e.error) || _isTlsError(e.message);

bool _isTlsError(Object? error) =>
    error is TlsException ||
    (error != null && error.toString().contains('CERTIFICATE_VERIFY_FAILED'));
