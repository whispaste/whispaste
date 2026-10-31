/// Turns a model download error into the text the user reads.
library;

import '../../services/download_disk_space.dart';
import '../../services/download_error_kind.dart';
import '../../services/download_tls_failure.dart';
import '../../services/model_download_service.dart' show formatModelSizeLabel;
import 'generated/app_localizations.dart';

/// The localized text for a download error. A disk-space refusal becomes the
/// sized message in the app language; every other message passes through.
String localizedDownloadError(L10n l10n, String? message) {
  if (message == downloadTlsErrorCode) return l10n.downloadTlsError;
  final shortage = DiskSpaceShortage.fromErrorCode(message);
  if (shortage == null) return message ?? '';
  return l10n.modelDownloadDiskSpaceShort(
    formatModelSizeLabel(shortage.neededBytes),
    formatModelSizeLabel(shortage.freeBytes),
  );
}

/// The text for a failed speech-model download, from its raw [message] and its
/// [kind]. A disk-space refusal keeps its sized message; anything else is named
/// by its category, so the page says what went wrong and what to do next.
String downloadFailureText(
  L10n l10n, {
  required String? message,
  required DownloadErrorKind? kind,
}) {
  if (DiskSpaceShortage.fromErrorCode(message) != null) {
    return localizedDownloadError(l10n, message);
  }
  return switch (kind) {
    DownloadErrorKind.network => l10n.modelDownloadFailed,
    DownloadErrorKind.checksum => l10n.modelDownloadFailedChecksum,
    DownloadErrorKind.storage => l10n.modelDownloadFailedStorage,
    DownloadErrorKind.tls => l10n.downloadTlsError,
    DownloadErrorKind.unknown || null => l10n.modelDownloadFailedUnknown,
  };
}
