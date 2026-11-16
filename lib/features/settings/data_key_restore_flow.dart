/// Restoring a lost data key, or deliberately starting over (#1167).
///
/// Offered in Settings → Privacy while the key is lost (marker present, key
/// gone), e.g. on a new device with the copied data folder. One dialog takes
/// the recovery code or the backup file from #1166, chosen or dropped. The
/// dialog says beforehand that the system may ask for permission (#1155);
/// nothing asks the system before the user taps "Restore".
///
/// A wrong or damaged backup changes nothing: the parser rejects it before
/// the store sees it, and the store refuses a key that does not match the
/// recorded fingerprint (`DataKeyStore.restore`).
///
/// "Create new key" sits in the same dialog, so the row keeps its one action
/// per state (#1165); it follows a destructive confirmation that says old
/// encrypted data stays unreadable. The store keeps the old files under
/// archive names (`DataKeyStore.replaceLostKey`).
///
/// Neither the code nor the file content is ever logged.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/config/data_key_access.dart';
import '../../core/config/data_key_backup.dart';
import '../../core/config/data_key_store.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/l10n/ltr_isolate.dart';
import '../../core/logging/app_logger.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/dialog.dart';
import '../../widgets/wp_audio_drop_zone.dart' show audioDropPauses;
import '../../widgets/wp_button.dart';
import '../../widgets/wp_text_field.dart';
import 'data_key_backup_flow.dart' show kDataKeyBackupNoticeArea;
import 'widgets/settings_notice.dart';

final _log = AppLogger('DataKeyRestore');

/// A backup file is a few hundred bytes; anything far larger is not one.
const _maxBackupFileBytes = 64 * 1024;

/// What the restore dialog ended with.
enum _RestoreOutcome {
  /// The key is back.
  restored,

  /// The user has no backup and wants to start over.
  replace,
}

/// The restore flow behind "Restore" in Settings → Privacy (#1165): the
/// dialog, then the notice. "Create new key" inside the dialog leads to the
/// warning of [startDataKeyReplace]. Returns true when the key is back.
///
/// [fromStartup] is the start screen of a locked history
/// (`DataKeyLockedScreen`): it leaves out "Create new key", because a new key
/// there would leave the encrypted history unreadable on the very screen that
/// promises nothing is lost, and it shows no notice, because the caller
/// reopens the database and the screen goes away.
Future<bool> startDataKeyRestore(
  BuildContext context, {
  bool fromStartup = false,
}) async {
  final l10n = L10n.of(context);
  audioDropPauses.value++;
  final _RestoreOutcome? outcome;
  try {
    outcome = await showWpFormDialog<_RestoreOutcome>(
      context: context,
      builder: (ctx, animation) =>
          _RestoreDialog(animation: animation, offerNewKey: !fromStartup),
    );
  } finally {
    audioDropPauses.value--;
  }
  if (!context.mounted) return outcome == _RestoreOutcome.restored;
  switch (outcome) {
    case _RestoreOutcome.restored:
      if (!fromStartup) _notice(context, l10n.dataKeyRestored);
      return true;
    case _RestoreOutcome.replace:
      await startDataKeyReplace(context);
      return false;
    case null:
      return false;
  }
}

/// Warns, then leaves the lost key behind and creates a new one.
Future<void> startDataKeyReplace(BuildContext context) async {
  final l10n = L10n.of(context);
  final access = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(dataKeyAccessProvider.notifier);
  final confirmed = await showWpConfirmDialog(
    context: context,
    title: l10n.dataKeyNewTitle,
    message: l10n.dataKeyNewWarning,
    confirmLabel: l10n.dataKeyNewConfirm,
    cancelLabel: l10n.actionCancel,
    destructive: true,
  );
  if (!confirmed || !context.mounted) return;
  final status = await access.replaceLostKey();
  if (!context.mounted) return;
  final created =
      status == DataKeyAccessStatus.ready ||
      status == DataKeyAccessStatus.fileFallback;
  _notice(
    context,
    created ? l10n.dataKeyNewDone : l10n.dataKeyNewFailed,
    failed: !created,
  );
}

/// The message for a rejected code or file.
String dataKeyBackupErrorText(L10n l10n, DataKeyBackupError error) =>
    switch (error) {
      DataKeyBackupError.empty => l10n.dataKeyRestoreErrorEmpty,
      DataKeyBackupError.invalidCharacter => l10n.dataKeyRestoreErrorCharacter,
      DataKeyBackupError.wrongLength => l10n.dataKeyRestoreErrorLength,
      DataKeyBackupError.checksumMismatch => l10n.dataKeyRestoreErrorTypo,
      DataKeyBackupError.notABackup => l10n.dataKeyRestoreErrorNotABackup,
      DataKeyBackupError.unsupportedVersion => l10n.dataKeyRestoreErrorVersion,
    };

/// The message for a backup the store refused.
String dataKeyRestoreFailureText(L10n l10n, DataKeyRestoreFailure failure) =>
    switch (failure) {
      DataKeyRestoreFailure.otherKey => l10n.dataKeyRestoreErrorOtherKey,
      DataKeyRestoreFailure.keyringLocked => l10n.dataKeyRestoreErrorLocked,
      DataKeyRestoreFailure.storageFailed => l10n.dataKeyRestoreErrorStorage,
    };

/// Reads a backup file at [path] and parses it. Unreadable, oversized or
/// non-text files count as "not a backup". Never logs the content.
Future<DataKeyBackupParse> readDataKeyBackupFile(String path) async {
  try {
    final file = File(path);
    if (await file.length() > _maxBackupFileBytes) {
      return const DataKeyBackupInvalid(DataKeyBackupError.notABackup);
    }
    final text = utf8.decode(await file.readAsBytes());
    return parseDataKeyBackupFile(text);
  } on FileSystemException catch (e) {
    _log.warning('Data key backup file not read: ${errorKind(e)}');
    return const DataKeyBackupInvalid(DataKeyBackupError.notABackup);
  } on FormatException {
    return const DataKeyBackupInvalid(DataKeyBackupError.notABackup);
  }
}

class _RestoreDialog extends ConsumerStatefulWidget {
  const _RestoreDialog({required this.animation, required this.offerNewKey});

  final Animation<double> animation;

  /// Whether "Create new key" is offered while the key is lost.
  final bool offerNewKey;

  @override
  ConsumerState<_RestoreDialog> createState() => _RestoreDialogState();
}

class _RestoreDialogState extends ConsumerState<_RestoreDialog> {
  final TextEditingController _code = TextEditingController();

  /// The parsed backup file, when one was chosen or dropped. Typing a code
  /// drops it again.
  DataKeyBackupParse? _file;
  String? _fileName;
  String? _error;
  bool _busy = false;
  bool _hovering = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _takeFile(String path) async {
    final parsed = await readDataKeyBackupFile(path);
    if (!mounted) return;
    final l10n = L10n.of(context);
    setState(() {
      _code.clear();
      _file = parsed;
      _fileName = p.basename(path);
      _error = switch (parsed) {
        DataKeyBackupInvalid(:final error) => dataKeyBackupErrorText(
          l10n,
          error,
        ),
        DataKeyBackupValid() => null,
      };
    });
  }

  Future<void> _chooseFile() async {
    final l10n = L10n.of(context);
    final picked = await openFile(
      acceptedTypeGroups: [
        XTypeGroup(
          label: l10n.dataKeyBackupFileType,
          extensions: const [dataKeyBackupExtension],
        ),
      ],
    );
    if (picked == null) return;
    await _takeFile(picked.path);
  }

  void _onDrop(DropDoneDetails details) {
    setState(() => _hovering = false);
    if (details.files.isEmpty) return;
    unawaited(_takeFile(details.files.first.path));
  }

  Future<void> _restore() async {
    final l10n = L10n.of(context);
    final parsed = _file ?? parseDataKeyRecoveryCode(_code.text);
    if (parsed case DataKeyBackupInvalid(:final error)) {
      setState(() => _error = dataKeyBackupErrorText(l10n, error));
      return;
    }
    final bytes = (parsed as DataKeyBackupValid).bytes;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ref
        .read(dataKeyAccessProvider.notifier)
        .restore(bytes);
    if (!mounted) return;
    switch (result) {
      case DataKeyRestored():
        Navigator.of(context).pop(_RestoreOutcome.restored);
      case DataKeyRestoreFailed(:final failure):
        _log.info('Data key not restored: ${failure.name}');
        setState(() {
          _busy = false;
          _error = dataKeyRestoreFailureText(l10n, failure);
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final lost = ref.watch(dataKeyAccessProvider) == DataKeyAccessStatus.lost;
    return WpFormDialogShell(
      animation: widget.animation,
      title: l10n.dataKeyRestoreTitle,
      // Says up front that the system may ask (#1155).
      subtitle: l10n.dataKeyRestoreIntro,
      fields: [
        // Codes are Latin letters and digits: always left to right.
        Directionality(
          textDirection: TextDirection.ltr,
          child: Semantics(
            identifier: 'data-key-restore-code',
            child: WpTextField(
              key: const ValueKey('data-key-restore-code'),
              controller: _code,
              variant: WpTextFieldVariant.form,
              hintText: l10n.dataKeyRestoreCodeLabel,
              semanticsLabel: l10n.dataKeyRestoreCodeLabel,
              autocorrect: false,
              onChanged: (_) {
                if (_file == null && _error == null) return;
                setState(() {
                  _file = null;
                  _fileName = null;
                  _error = null;
                });
              },
            ),
          ),
        ),
        const SizedBox(height: WpSpacing.md),
        DropTarget(
          onDragEntered: (_) => setState(() => _hovering = true),
          onDragExited: (_) => setState(() => _hovering = false),
          onDragDone: _onDrop,
          child: Semantics(
            identifier: 'data-key-restore-drop',
            container: true,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(WpSpacing.md),
              decoration: BoxDecoration(
                color: _hovering ? WpColors.accentSubtle : null,
                borderRadius: WpRadius.borderMd,
                border: Border.all(
                  color: _hovering ? WpColors.accent : WpColors.borderDefault,
                ),
              ),
              child: Column(
                children: [
                  Text(
                    _fileName == null
                        ? l10n.dataKeyRestoreDropHint
                        : l10n.dataKeyRestoreFileChosen(ltrIsolate(_fileName!)),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: WpColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: WpSpacing.sm),
                  WpButton(
                    testId: 'data-key-restore-choose-file',
                    label: l10n.dataKeyRestoreChooseFile,
                    variant: WpButtonVariant.secondary,
                    onPressed: _busy ? null : () => unawaited(_chooseFile()),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_error case final error?) ...[
          const SizedBox(height: WpSpacing.sm),
          Semantics(
            identifier: 'data-key-restore-error',
            liveRegion: true,
            child: Text(
              error,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: WpColors.error,
              ),
            ),
          ),
        ],
      ],
      actions: [
        // Without a backup the only way on is a new key (after a warning).
        if (lost && widget.offerNewKey)
          WpDialogAction<Object?>(
            label: l10n.dataKeyNewAction,
            testId: 'data-key-restore-new',
            role: WpDialogActionRole.alternative,
            enabled: !_busy,
            value: _RestoreOutcome.replace,
          ),
        WpDialogAction<Object?>(
          label: l10n.actionCancel,
          testId: 'data-key-restore-cancel',
          role: WpDialogActionRole.cancel,
        ),
        WpDialogAction<Object?>(
          label: l10n.dataKeyRestoreConfirm,
          testId: 'data-key-restore-confirm',
          role: WpDialogActionRole.primary,
          isLoading: _busy,
          onPressed: _busy ? null : () => unawaited(_restore()),
        ),
      ],
    );
  }
}

void _notice(BuildContext context, String message, {bool failed = false}) {
  showSettingsNotice(
    context,
    area: kDataKeyBackupNoticeArea,
    id: failed ? 'data-key-restore-failed' : 'data-key-restore-done',
    message: message,
    failed: failed,
  );
}
