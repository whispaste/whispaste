/// Backing up the data key from Settings → Privacy (#1166).
///
/// Offered once the key exists (status ready or fileFallback). One dialog
/// says what a backup is worth and offers two equal ways: show the recovery
/// code (write it down or copy it) or save the backup file. Both hold the
/// same key (`data_key_backup.dart`).
///
/// Neither the code nor the file content is ever logged, sent to Sentry or
/// kept in app state beyond the open dialog. Copying marks the text as
/// confidential, so OS clipboard history and the app's own clipboard history
/// skip it.
library;

import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../core/config/data_key_access.dart';
import '../../core/config/data_key_backup.dart';
import '../../core/config/data_key_store.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/logging/app_logger.dart';
import '../../core/platform/posix_native.dart';
import '../../core/theme/tokens.dart';
import '../../services/clipboard_history/app_clipboard.dart';
import '../../services/desktop_paste/desktop_paste_controller.dart';
import '../../widgets/dialog.dart';
import '../../widgets/wp_button.dart';
import 'widgets/settings_notice.dart';

final _log = AppLogger('DataKeyBackup');

/// Notice area of the data-key row in Settings → Privacy.
const kDataKeyBackupNoticeArea = 'data-key-backup';

/// Owner-only (0600) for the saved backup file on macOS and Linux.
const _ownerOnlyFile = 0x180;

/// The row's subtitle addition: when the key was last backed up.
String dataKeyBackupStatusText(L10n l10n, DateTime? backedUpAt) {
  if (backedUpAt == null) return l10n.dataKeyNotBackedUp;
  final locale = l10n.localeName;
  final date = DateFormat.yMd(locale).add_Hm().format(backedUpAt.toLocal());
  return l10n.dataKeyBackedUpAt(date);
}

/// Whether the key exists, so it can be backed up.
bool dataKeyStatusOffersBackup(DataKeyAccessStatus status) =>
    status == DataKeyAccessStatus.ready ||
    status == DataKeyAccessStatus.fileFallback;

/// "Back up" / "Back up again" for the data-key row.
Widget dataKeyBackupButton({
  required BuildContext context,
  required WidgetRef ref,
  required L10n l10n,
  required String testId,
}) {
  final backedUp = ref.watch(dataKeyBackupProvider) != null;
  return WpButton(
    testId: testId,
    label: backedUp ? l10n.dataKeyBackupAgain : l10n.dataKeyBackupAction,
    variant: WpButtonVariant.secondary,
    onPressed: () => unawaited(startDataKeyBackup(context, ref)),
  );
}

enum _BackupWay { code, file }

enum _CodeOutcome { copied, done }

/// Runs the backup dialog. Records the time only after a finished backup.
Future<void> startDataKeyBackup(BuildContext context, WidgetRef ref) async {
  final l10n = L10n.of(context);
  final way = await showWpDialog<_BackupWay>(
    context: context,
    title: l10n.dataKeyBackupTitle,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.dataKeyBackupIntro),
        const SizedBox(height: WpSpacing.sm),
        Semantics(
          identifier: 'data-key-backup-warning',
          child: Text(l10n.dataKeyBackupWarning),
        ),
      ],
    ),
    actions: [
      WpDialogAction<_BackupWay>(
        label: l10n.actionCancel,
        testId: 'data-key-backup-cancel',
        role: WpDialogActionRole.cancel,
      ),
      WpDialogAction<_BackupWay>(
        label: l10n.dataKeyBackupSaveFile,
        testId: 'data-key-backup-save-file',
        value: _BackupWay.file,
      ),
      WpDialogAction<_BackupWay>(
        label: l10n.dataKeyBackupShowCode,
        testId: 'data-key-backup-show-code',
        role: WpDialogActionRole.primary,
        value: _BackupWay.code,
      ),
    ],
  );
  if (way == null || !context.mounted) return;
  final key = await ref.read(dataKeyAccessProvider.notifier).keyForBackup();
  if (!context.mounted) return;
  if (key == null) {
    _notice(context, l10n.dataKeyBackupUnavailable, failed: true);
    return;
  }
  switch (way) {
    case _BackupWay.code:
      await _showCode(context, ref, key);
    case _BackupWay.file:
      await _saveFile(context, ref, key);
  }
}

Future<void> _showCode(BuildContext context, WidgetRef ref, DataKey key) async {
  final l10n = L10n.of(context);
  final code = dataKeyRecoveryCode(key.bytes);
  final outcome = await showWpDialog<_CodeOutcome>(
    context: context,
    title: l10n.dataKeyBackupCodeTitle,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.dataKeyBackupCodeHint),
        const SizedBox(height: WpSpacing.md),
        // Always left to right (also in Hebrew) and not selectable, so the
        // only way out is the confidential copy below.
        Directionality(
          textDirection: TextDirection.ltr,
          child: Semantics(
            identifier: 'data-key-backup-code',
            child: Text(
              code,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 16,
                height: 1.6,
                letterSpacing: 1,
              ),
            ),
          ),
        ),
        const SizedBox(height: WpSpacing.sm),
        Text(l10n.dataKeyBackupWarning),
      ],
    ),
    actions: [
      WpDialogAction<_CodeOutcome>(
        label: l10n.dataKeyBackupCopy,
        testId: 'data-key-backup-copy',
        value: _CodeOutcome.copied,
      ),
      WpDialogAction<_CodeOutcome>(
        label: l10n.dataKeyBackupDone,
        testId: 'data-key-backup-done',
        role: WpDialogActionRole.primary,
        value: _CodeOutcome.done,
      ),
    ],
  );
  if (outcome == null) return;
  if (outcome == _CodeOutcome.copied) {
    await _copyConfidential(ref, code);
  }
  await ref.read(dataKeyBackupProvider.notifier).record(key);
  if (outcome == _CodeOutcome.copied && context.mounted) {
    _notice(context, l10n.dataKeyBackupCopied);
  }
}

/// Copies [text] marked as confidential: the app's own clipboard history
/// skips it, and the OS history skips it where the platform allows
/// (macOS concealed/transient type, Windows history exclusion, Linux
/// password-manager hint). No log line, not even for the fallback.
Future<void> _copyConfidential(WidgetRef ref, String text) async {
  AppClipboard.markTransientWrite(text);
  final controller = ref.read(desktopPasteControllerProvider);
  final excluded =
      await controller?.writeClipboardTextExcludingHistory(text) ?? false;
  if (excluded) return;
  await Clipboard.setData(ClipboardData(text: text));
}

Future<void> _saveFile(BuildContext context, WidgetRef ref, DataKey key) async {
  final l10n = L10n.of(context);
  final location = await getSaveLocation(
    acceptedTypeGroups: [
      XTypeGroup(
        label: l10n.dataKeyBackupFileType,
        extensions: const [dataKeyBackupExtension],
      ),
    ],
    suggestedName: dataKeyBackupFileName,
  );
  if (location == null || !context.mounted) return;
  final saved = await writeDataKeyBackupFile(
    location.path,
    key.bytes,
    DateTime.now(),
    posix: dataKeyBackupNeedsPosixPermissions,
  );
  if (!context.mounted) return;
  if (!saved) {
    _notice(context, l10n.dataKeyBackupFileFailed, failed: true);
    return;
  }
  await ref.read(dataKeyBackupProvider.notifier).record(key);
  if (context.mounted) _notice(context, l10n.dataKeyBackupFileSaved);
}

/// Writes the backup file at [path], owner-only on POSIX before the key goes
/// in. False on any failure; a half-written file is removed.
Future<bool> writeDataKeyBackupFile(
  String path,
  List<int> key,
  DateTime createdAt, {
  required bool posix,
}) async {
  final file = File(path);
  try {
    await file.writeAsString('', flush: true);
    if (posix && !nativeChmod(file.path, _ownerOnlyFile)) {
      await file.delete();
      return false;
    }
    await file.writeAsString(
      dataKeyBackupFileContents(key, createdAt),
      flush: true,
    );
    return true;
  } on FileSystemException catch (e) {
    // Only the error type and OS code, never the path or content.
    _log.warning('Data key backup file not written: ${errorKind(e)}');
    if (file.existsSync()) {
      await file.delete().then<void>((_) {}, onError: (Object _) {});
    }
    return false;
  }
}

void _notice(BuildContext context, String message, {bool failed = false}) {
  showSettingsNotice(
    context,
    area: kDataKeyBackupNoticeArea,
    id: failed ? 'data-key-backup-failed' : 'data-key-backup-done',
    message: message,
    failed: failed,
  );
}
