/// The error of a failed model download, with the two ways forward (#1513):
/// "Try again" and, as the last resort, "Open model folder" to put the file
/// there by hand.
library;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/l10n/download_error_text.dart';
import '../core/l10n/generated/app_localizations.dart';
import '../core/theme/tokens.dart';
import '../services/download_error_kind.dart';
import '../services/model_download_service.dart'
    show modelDeleteFailedError, modelDeleteInUseError;
import '../services/model_folder.dart';
import 'wp_button.dart';
import 'wp_error_notice.dart';

/// Cause and next step of a failed download in everyday words
/// ([downloadFailureText]), a retry and a button that opens [folder].
///
/// [testIdPrefix] names the place (`settings-stt`, `speech-parakeet`,
/// `smart-mode`); the buttons are `<prefix>-download-retry` and
/// `<prefix>-open-model-folder`.
class WpModelDownloadErrorNotice extends StatelessWidget {
  const WpModelDownloadErrorNotice({
    super.key,
    required this.message,
    required this.kind,
    required this.folder,
    required this.onRetry,
    required this.testIdPrefix,
    this.openFolder = openModelFolder,
  });

  /// Raw error code or message of the download state (log only, unless it is
  /// a disk-space code).
  final String? message;
  final DownloadErrorKind? kind;

  /// Folder the model file belongs in.
  final String Function() folder;
  final VoidCallback onRetry;
  final String testIdPrefix;

  /// Opens the folder; replaced in tests.
  final Future<bool> Function(String path) openFolder;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final cause = downloadFailureText(l10n, message: message, kind: kind);
    // A failed delete is no download problem: neither a retry nor the
    // folder helps there.
    if (message == modelDeleteInUseError || message == modelDeleteFailedError) {
      return WpErrorNotice(cause: cause);
    }
    return Semantics(
      container: true,
      liveRegion: true,
      identifier: '$testIdPrefix-download-error',
      child: WpErrorNotice(
        cause: cause,
        nextStep: l10n.modelDownloadManualHint,
        action: Wrap(
          spacing: WpSpacing.xs,
          runSpacing: WpSpacing.xs,
          children: [
            WpButton(
              testId: '$testIdPrefix-download-retry',
              label: l10n.actionRetry,
              icon: LucideIcons.refreshCw,
              variant: WpButtonVariant.secondary,
              size: WpButtonSize.dense,
              onPressed: onRetry,
            ),
            WpButton(
              testId: '$testIdPrefix-open-model-folder',
              label: l10n.modelOpenFolder,
              icon: LucideIcons.folderOpen,
              variant: WpButtonVariant.ghost,
              tone: WpButtonTone.neutral,
              size: WpButtonSize.dense,
              onPressed: () => openFolder(folder()),
            ),
          ],
        ),
      ),
    );
  }
}
