/// Turns a model download error into the text the user reads.
library;

import '../../services/download_disk_space.dart';
import '../../services/model_download_service.dart' show formatModelSizeLabel;
import 'generated/app_localizations.dart';

/// The localized text for a download error. A disk-space refusal becomes the
/// sized message in the app language; every other message passes through.
String localizedDownloadError(L10n l10n, String? message) {
  final shortage = DiskSpaceShortage.fromErrorCode(message);
  if (shortage == null) return message ?? '';
  return l10n.modelDownloadDiskSpaceShort(
    formatModelSizeLabel(shortage.neededBytes),
    formatModelSizeLabel(shortage.freeBytes),
  );
}
