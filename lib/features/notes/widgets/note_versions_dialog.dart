/// Version history of the open note, newest first (ticket).
///
/// Each entry shows what that snapshot changed compared with the one before
/// it. Restoring keeps the replaced state as a version, so a restore can be
/// undone the same way. Restoring and deleting both ask first; deleting a
/// version cannot be undone. Resolves to `true` when a version was restored,
/// so the page can reload the editor text.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/data/database.dart';
import '../../../core/data/note_version_limits.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/dialog.dart';
import '../../../widgets/version_compare_dialog.dart';
import '../../../widgets/wp_icon_button.dart';
import '../data/note_line_diff.dart';
import '../data/notes_actions.dart';

final _log = AppLogger('NoteVersions');

const int _previewLineLimit = 4;

Future<bool?> showNoteVersionsDialog({
  required BuildContext context,
  required String noteId,
}) {
  final l10n = L10n.of(context);
  return showWpDialog<bool>(
    context: context,
    title: l10n.notesMenuVersions,
    // The list needs a bounded height inside the dialog's scroll body.
    content: SizedBox(height: 420, child: _NoteVersionsList(noteId: noteId)),
    // Shorter than the shared dialog token: the list is already in memory and
    // should not wait behind a 300 ms fade.
    transition: WpMotion.normal,
    actions: [
      WpDialogAction(
        label: l10n.historyClose,
        testId: 'notes-versions-close',
        role: WpDialogActionRole.primary,
        value: false,
      ),
    ],
  );
}

Future<void> _showVersionError(BuildContext context) {
  final l10n = L10n.of(context);
  return showWpDialog<void>(
    context: context,
    title: l10n.notesMenuVersions,
    content: Text(l10n.errorGeneric),
    actions: [
      WpDialogAction(
        label: l10n.historyClose,
        testId: 'notes-version-error-close',
        role: WpDialogActionRole.primary,
      ),
    ],
  );
}

class _NoteVersionsList extends ConsumerStatefulWidget {
  const _NoteVersionsList({required this.noteId});

  final String noteId;

  @override
  ConsumerState<_NoteVersionsList> createState() => _NoteVersionsListState();
}

class _NoteVersionsListState extends ConsumerState<_NoteVersionsList> {
  /// Unpacked body of each version by id. A version never changes, so a text
  /// is unpacked once, not on every build of every row.
  final Map<String, String> _texts = {};

  String _textOf(NoteVersion version) => _texts.putIfAbsent(
    version.id,
    () => decodeNoteVersionBody(version.content),
  );

  @override
  Widget build(BuildContext context) {
    final noteId = widget.noteId;
    final l10n = L10n.of(context);
    final versions = ref.watch(noteVersionsProvider(noteId));
    return versions.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => Center(child: Text(l10n.errorGeneric)),
      data: (list) {
        _texts.removeWhere((id, _) => !list.any((v) => v.id == id));
        if (list.isEmpty) {
          return Center(
            child: Text(
              l10n.notesVersionsEmpty,
              style: TextStyle(color: WpColors.textMuted),
            ),
          );
        }
        return Semantics(
          identifier: 'notes-version-list',
          child: ListView.separated(
            key: const ValueKey('notes-version-list'),
            itemCount: list.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final version = list[index];
              // The next entry is the older snapshot: this version's changes
              // are what it added on top of that one.
              final older = index + 1 < list.length
                  ? _textOf(list[index + 1])
                  : '';
              return _VersionRow(
                version: version,
                content: _textOf(version),
                olderContent: older,
              );
            },
          ),
        );
      },
    );
  }
}

class _VersionRow extends ConsumerWidget {
  const _VersionRow({
    required this.version,
    required this.content,
    required this.olderContent,
  });

  final NoteVersion version;
  final String content;
  final String olderContent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final materialL10n = MaterialLocalizations.of(context);
    final when = TimeOfDay.fromDateTime(version.createdAt);
    final stamp =
        '${materialL10n.formatMediumDate(version.createdAt)} '
        '${materialL10n.formatTimeOfDay(when)}';
    final diff = diffNoteLines(olderContent, content);
    final changed = diff?.where((l) => l.kind != NoteDiffKind.same).toList();
    final rowId = 'notes-version-row-${version.id}';

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
                  if (changed == null)
                    Text(
                      l10n.notesVersionTooLarge,
                      style: TextStyle(color: WpColors.textMuted),
                    )
                  else
                    for (final line in changed.take(_previewLineLimit))
                      Text(
                        '${line.kind == NoteDiffKind.added ? '+' : '−'} '
                        '${line.text}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: line.kind == NoteDiffKind.added
                              ? WpColors.textPrimary
                              : WpColors.textMuted,
                        ),
                      ),
                ],
              ),
            ),
            WpIconButton.ghost(
              key: ValueKey('notes-version-compare-${version.id}'),
              icon: LucideIcons.gitCompare,
              tooltip: l10n.versionCompare,
              testId: 'notes-version-compare-${version.id}',
              onPressed: () => _compare(context, ref),
            ),
            WpIconButton.ghost(
              key: ValueKey('notes-version-restore-${version.id}'),
              icon: LucideIcons.undo2,
              tooltip: l10n.notesRestore,
              testId: 'notes-version-restore-${version.id}',
              onPressed: () => _restore(context, ref, l10n),
            ),
            WpIconButton.ghost(
              key: ValueKey('notes-version-delete-${version.id}'),
              icon: LucideIcons.trash2,
              tooltip: l10n.notesVersionDelete,
              testId: 'notes-version-delete-${version.id}',
              onPressed: () => _delete(context, ref, l10n),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _compare(BuildContext context, WidgetRef ref) async {
    final actions = ref.read(notesActionsProvider);
    final note = await actions.getNote(version.noteId);
    if (note == null || !context.mounted) return;
    final changed = await showWpVersionCompareDialog(
      context: context,
      idPrefix: 'notes',
      versionText: content,
      currentText: note.content,
      apply: (next) async {
        // Keep the text being replaced as a version, then store the new one.
        await actions.snapshot(
          note.id,
          title: note.title,
          content: note.content,
        );
        await actions.save(note.id, next);
      },
    );
    if (changed && context.mounted) Navigator.of(context).pop(true);
  }

  Future<void> _restore(BuildContext context, WidgetRef ref, L10n l10n) async {
    final confirmed = await showWpConfirmDialog(
      context: context,
      title: l10n.notesRestore,
      message: l10n.notesVersionRestoreMessage,
      confirmLabel: l10n.notesRestore,
      cancelLabel: l10n.actionCancel,
      // Restoring overwrites the current text (the replaced state is kept as a
      // version, but the editor content changes).
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    try {
      final restored = await ref
          .read(notesActionsProvider)
          .restoreVersion(version.id);
      if (!restored) throw StateError('version ${version.id} not found');
    } catch (e, st) {
      _log.warning('Could not restore note version', e, st);
      if (context.mounted) await _showVersionError(context);
      return;
    }
    if (context.mounted) Navigator.of(context).pop(true);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, L10n l10n) async {
    final confirmed = await showWpConfirmDialog(
      context: context,
      title: l10n.notesVersionDelete,
      message: l10n.notesVersionDeleteMessage,
      confirmLabel: l10n.notesVersionDelete,
      cancelLabel: l10n.actionCancel,
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    try {
      await ref.read(notesActionsProvider).deleteVersion(version.id);
    } catch (e, st) {
      _log.warning('Could not delete note version', e, st);
      if (context.mounted) await _showVersionError(context);
    }
  }
}
