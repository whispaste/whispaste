/// Version list of a recording transcript (#635), newest first.
///
/// Every row shows when the text was kept, how it came to be and how long it
/// is. Restoring replaces the transcript and keeps the replaced text as a
/// version, so a restore is undone the same way. The original log and the
/// Smart Mode result are not part of this list and stay as they are.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/data/database.dart';
import '../../../core/data/entry_version_rules.dart';
import '../../../core/data/note_version_limits.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/dialog.dart';
import '../../../widgets/version_compare_dialog.dart';
import '../../../widgets/wp_icon_button.dart';
import '../data/history_detail_provider.dart';

final _log = AppLogger('TranscriptVersions');

final _entryVersionsProvider = StreamProvider.autoDispose
    .family<List<EntryVersion>, String>(
      (ref, entryId) =>
          ref.watch(historyDatabaseProvider).watchEntryVersions(entryId),
    );

String _sourceLabel(L10n l10n, EntryVersionSource source) => switch (source) {
  EntryVersionSource.dictated => l10n.historyVersionSourceDictated,
  EntryVersionSource.typed => l10n.historyVersionSourceTyped,
  EntryVersionSource.converted => l10n.historyVersionSourceConverted,
  EntryVersionSource.restored => l10n.historyVersionSourceRestored,
};

/// Opens the list. Resolves to `true` when a version was restored.
Future<bool?> showTranscriptVersionsDialog({
  required BuildContext context,
  required String entryId,
}) {
  final l10n = L10n.of(context);
  return showWpDialog<bool>(
    context: context,
    title: l10n.historyVersions,
    content: SizedBox(
      height: 420,
      child: _TranscriptVersionsList(entryId: entryId),
    ),
    transition: WpMotion.normal,
    actions: [
      WpDialogAction(
        label: l10n.historyClose,
        testId: 'history-versions-close',
        role: WpDialogActionRole.primary,
        value: false,
      ),
    ],
  );
}

class _TranscriptVersionsList extends ConsumerWidget {
  const _TranscriptVersionsList({required this.entryId});

  final String entryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final versions = ref.watch(_entryVersionsProvider(entryId));
    return versions.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => Center(child: Text(l10n.errorGeneric)),
      data: (list) {
        if (list.isEmpty) {
          return Center(
            child: Text(
              l10n.historyVersionsEmpty,
              style: TextStyle(color: WpColors.textMuted),
            ),
          );
        }
        final atCap = list.length >= EntryVersionLimits.standard.maxCount;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (atCap)
              Semantics(
                identifier: 'history-versions-limit',
                child: Padding(
                  padding: const EdgeInsets.only(bottom: WpSpacing.xs),
                  child: Text(
                    l10n.historyVersionsLimit(
                      EntryVersionLimits.standard.maxCount,
                    ),
                    style: TextStyle(
                      fontSize: WpTypography.caption,
                      color: WpColors.textMuted,
                    ),
                  ),
                ),
              ),
            Expanded(
              child: Semantics(
                identifier: 'history-version-list',
                child: ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) =>
                      _VersionRow(entryId: entryId, version: list[index]),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _VersionRow extends ConsumerWidget {
  const _VersionRow({required this.entryId, required this.version});

  final String entryId;
  final EntryVersion version;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final material = MaterialLocalizations.of(context);
    final stamp =
        '${material.formatMediumDate(version.createdAt)} '
        '${material.formatTimeOfDay(TimeOfDay.fromDateTime(version.createdAt))}';
    final source = _sourceLabel(
      l10n,
      EntryVersionSource.fromName(version.source),
    );
    final text = decodeNoteVersionBody(version.content);
    final summary = '$source · ${l10n.historyVersionChars(text.length)}';
    final preview = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    final rowId = 'history-version-row-${version.id}';
    return Semantics(
      identifier: rowId,
      child: Padding(
        key: ValueKey(rowId),
        padding: const EdgeInsets.symmetric(
          horizontal: WpSpacing.sm,
          vertical: WpSpacing.xs,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stamp,
                    style: TextStyle(
                      fontSize: WpTypography.body,
                      fontWeight: FontWeight.w600,
                      color: WpColors.textPrimary,
                    ),
                  ),
                  Text(summary, style: TextStyle(color: WpColors.textMuted)),
                  if (preview.isNotEmpty)
                    Text(
                      preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: WpColors.textPrimary),
                    ),
                ],
              ),
            ),
            WpIconButton.ghost(
              key: ValueKey('history-version-compare-${version.id}'),
              icon: LucideIcons.gitCompare,
              tooltip: l10n.versionCompare,
              testId: 'history-version-compare-${version.id}',
              onPressed: () => _compare(context, ref, text),
            ),
            WpIconButton.ghost(
              key: ValueKey('history-version-restore-${version.id}'),
              icon: LucideIcons.undo2,
              tooltip: l10n.notesRestore,
              testId: 'history-version-restore-${version.id}',
              onPressed: () => _restore(context, ref, l10n),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _compare(
    BuildContext context,
    WidgetRef ref,
    String versionText,
  ) async {
    final current = ref.read(historyDetailProvider(entryId)).value;
    if (current == null) return;
    final changed = await showWpVersionCompareDialog(
      context: context,
      idPrefix: 'history',
      versionText: versionText,
      currentText: current.entry.content,
      apply: (next) =>
          ref.read(historyDetailProvider(entryId).notifier).updateContent(next),
    );
    if (changed && context.mounted) Navigator.of(context).pop(true);
  }

  Future<void> _restore(BuildContext context, WidgetRef ref, L10n l10n) async {
    final confirmed = await showWpConfirmDialog(
      context: context,
      title: l10n.notesRestore,
      message: l10n.historyVersionRestoreMessage,
      confirmLabel: l10n.notesRestore,
      cancelLabel: l10n.actionCancel,
    );
    if (!confirmed || !context.mounted) return;
    try {
      final restored = await ref
          .read(historyDetailProvider(entryId).notifier)
          .restoreVersion(version.id);
      if (!restored) throw StateError('version ${version.id} not restorable');
    } catch (e, st) {
      _log.warning('Could not restore transcript version', e, st);
      if (context.mounted) {
        await showWpDialog<void>(
          context: context,
          title: l10n.historyVersions,
          content: Text(l10n.errorGeneric),
          actions: [
            WpDialogAction(
              label: l10n.historyClose,
              testId: 'history-version-error-close',
              role: WpDialogActionRole.primary,
            ),
          ],
        );
      }
      return;
    }
    if (context.mounted) Navigator.of(context).pop(true);
  }
}
