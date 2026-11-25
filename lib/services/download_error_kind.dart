import 'dart:async' show TimeoutException;
import 'dart:io';

import 'package:dio/dio.dart';

import 'download_tls_failure.dart';
import 'http_model_fetcher.dart'
    show
        DownloadChecksumException,
        DownloadLengthException,
        DownloadWrongResponseException;

/// Why a model download failed, as far as the user can act on it. The raw
/// exception text goes to the log only; the UI maps this to a sentence.
enum DownloadErrorKind {
  /// The device has no connection to the download server (no network, no DNS,
  /// connection refused). The text is `l10n.modelDownloadOffline`; on the setup
  /// page it also gets a retry and a way to install the model by hand.
  offline,

  /// Connection lost mid-transfer, server error or stalled transfer —
  /// retrying helps.
  network,

  /// The file arrived but failed its size or hash check and was removed, or
  /// every source answered with something else (a web page, another file).
  checksum,

  /// The file could not be written (disk full, no permission).
  storage,

  /// The secure connection could not be verified (certificate or TLS error).
  /// Shown with its own next step, see `l10n.downloadTlsError`.
  tls,

  /// Anything the categories above do not cover.
  unknown,
}

/// Maps an exception thrown while fetching a model to a [DownloadErrorKind].
/// Cancellation is not an error and never reaches this.
DownloadErrorKind classifyDownloadError(Object error) {
  if (error is DioException) {
    if (isTlsDownloadFailure(error)) return DownloadErrorKind.tls;
    final inner = error.error;
    if (inner is FileSystemException) return DownloadErrorKind.storage;
    // Dio reports a connection that could not be opened (no network, no
    // DNS, refused) as one of these two types. A socket error of another
    // type comes from a connection that was already open, so it was lost
    // mid-transfer and retrying helps.
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout) {
      return DownloadErrorKind.offline;
    }
    return DownloadErrorKind.network;
  }
  if (error is FileSystemException) return DownloadErrorKind.storage;
  if (error is DownloadChecksumException ||
      error is DownloadLengthException ||
      error is DownloadWrongResponseException) {
    return DownloadErrorKind.checksum;
  }
  if (error is SocketException) return DownloadErrorKind.offline;
  if (error is HttpException || error is TimeoutException) {
    return DownloadErrorKind.network;
  }
  return DownloadErrorKind.unknown;
}

/// Whether a failed download is caused by the user's connection rather than
/// by the app: no network, a lost or stalled transfer, a server error or a
/// TLS failure. The UI already offers a retry for these, so they are logged
/// as warnings and stay out of Sentry (rule 2026-10-27: offline is an
/// expected state). A full disk, a failed hash check or anything unknown
/// keeps its error level.
bool isConnectionDownloadFailure(Object error) =>
    switch (classifyDownloadError(error)) {
      DownloadErrorKind.offline ||
      DownloadErrorKind.network ||
      DownloadErrorKind.tls => true,
      _ => false,
    };
