import 'dart:async' show TimeoutException;
import 'dart:io';

import 'package:dio/dio.dart';

/// Why a model download failed, as far as the user can act on it. The raw
/// exception text goes to the log only; the UI maps this to a sentence.
enum DownloadErrorKind {
  /// Connection lost, server error or stalled transfer — retrying helps.
  network,

  /// The file arrived but failed its size or hash check and was removed.
  checksum,

  /// The file could not be written (disk full, no permission).
  storage,

  /// Anything the categories above do not cover.
  unknown,
}

/// Maps an exception thrown while fetching a model to a [DownloadErrorKind].
/// Cancellation is not an error and never reaches this.
DownloadErrorKind classifyDownloadError(Object error) {
  if (error is DioException) {
    final inner = error.error;
    if (inner is FileSystemException) return DownloadErrorKind.storage;
    return DownloadErrorKind.network;
  }
  if (error is FileSystemException) return DownloadErrorKind.storage;
  if (error is SocketException ||
      error is HttpException ||
      error is TimeoutException) {
    return DownloadErrorKind.network;
  }
  return DownloadErrorKind.unknown;
}
