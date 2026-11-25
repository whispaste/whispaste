/// Dialogs for the note folders (#659, ADR 0034): naming a folder, the
/// question before a folder with notes is deleted, and "Move to folder…".
library;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/data/database.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/dialog.dart';
import '../../../widgets/wp_filter_chip.dart';
import '../../../widgets/wp_text_field.dart';

/// Asks for a folder name. Returns the trimmed name, or null when cancelled.
Future<String?> showNoteFolderNameDialog(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String initial = '',
}) => showWpFormDialog<String>(
  context: context,
  builder: (context, animation) => _FolderNameDialog(
    animation: animation,
    title: title,
    confirmLabel: confirmLabel,
    initial: initial,
  ),
);

class _FolderNameDialog extends StatefulWidget {
  const _FolderNameDialog({
    required this.animation,
    required this.title,
    required this.confirmLabel,
    required this.initial,
  });

  final Animation<double> animation;
  final String title;
  final String confirmLabel;
  final String initial;

  @override
  State<_FolderNameDialog> createState() => _FolderNameDialogState();
}

class _FolderNameDialogState extends State<_FolderNameDialog> {
  late final _name = TextEditingController(text: widget.initial)
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.initial.length,
    );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String get _value => _name.text.trim();

  void _confirm() {
    if (_value.isNotEmpty) Navigator.of(context).pop(_value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final valid = _value.isNotEmpty;
    return WpFormDialogShell(
      animation: widget.animation,
      title: widget.title,
      subtitle: l10n.notesFolderNameSubtitle,
      fields: [
        WpTextField(
          testId: 'notes-folder-name-field',
          key: const ValueKey('notes-folder-name-field'),
          controller: _name,
          variant: WpTextFieldVariant.form,
          hintText: l10n.notesFolderNameHint,
          semanticsLabel: l10n.notesFolderNameHint,
          autofocus: true,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _confirm(),
        ),
      ],
      actions: [
        WpDialogAction<Object?>(
          label: l10n.actionCancel,
          testId: 'notes-folder-name-cancel',
          role: WpDialogActionRole.cancel,
        ),
        WpDialogAction<Object?>(
          label: widget.confirmLabel,
          testId: 'notes-folder-name-confirm',
          role: WpDialogActionRole.primary,
          enabled: valid,
          onPressed: valid ? _confirm : null,
        ),
      ],
    );
  }
}

/// What happens to the notes of a folder that is deleted.
enum NoteFolderDeleteChoice { keepNotes, trashNotes }

/// Asks before folder [name] is deleted (ADR 0034: never delete notes
/// without asking). An empty folder only needs a confirm; one holding
/// [noteCount] notes asks whether they stay (moved to the top level, the
/// recommendation) or go to the trash. Returns null when cancelled.
Future<NoteFolderDeleteChoice?> showNoteFolderDeleteDialog(
  BuildContext context, {
  required String name,
  required int noteCount,
}) async {
  final l10n = L10n.of(context);
  if (noteCount == 0) {
    final ok = await showWpConfirmDialog(
      context: context,
      title: l10n.notesFolderDeleteTitle(name),
      message: l10n.notesFolderDeleteEmptyMessage,
      confirmLabel: l10n.notesFolderDelete,
      cancelLabel: l10n.actionCancel,
      destructive: true,
    );
    return ok ? NoteFolderDeleteChoice.keepNotes : null;
  }
  return showWpChoiceDialog<NoteFolderDeleteChoice?>(
    context: context,
    title: l10n.notesFolderDeleteTitle(name),
    body: l10n.notesFolderDeleteMessage(noteCount),
    dismissValue: null,
    choices: [
      WpDialogAction(
        label: l10n.actionCancel,
        testId: 'notes-folder-delete-cancel',
        role: WpDialogActionRole.cancel,
      ),
      WpDialogAction(
        label: l10n.notesFolderDeleteKeep,
        testId: 'notes-folder-delete-keep',
        role: WpDialogActionRole.primary,
        value: NoteFolderDeleteChoice.keepNotes,
      ),
      WpDialogAction(
        label: l10n.notesFolderDeleteTrash,
        testId: 'notes-folder-delete-trash',
        role: WpDialogActionRole.destructive,
        value: NoteFolderDeleteChoice.trashNotes,
      ),
    ],
  );
}

/// Where "Move to folder…" sends notes: [folderId] (null = no folder), or a
/// folder that is created first when [createNew] is set.
class NoteFolderMoveTarget {
  const NoteFolderMoveTarget(this.folderId) : createNew = false;
  const NoteFolderMoveTarget.createNew() : folderId = null, createNew = true;

  final String? folderId;
  final bool createNew;
}

/// The folder's name as a list shows it: a subfolder as "Parent / Child".
String noteFolderPath(NoteFolder folder, Map<String, NoteFolder> byId) {
  final parent = folder.parentId == null ? null : byId[folder.parentId];
  return parent == null ? folder.name : '${parent.name} / ${folder.name}';
}

/// Asks where [count] notes go. [currentFolderId] marks the folder they
/// share; with [sharesFolder] false (a mixed selection) nothing is marked.
/// Every target is one chip, reachable by Tab and Enter; a pick closes the
/// dialog. Returns null when cancelled.
Future<NoteFolderMoveTarget?> showMoveToFolderDialog(
  BuildContext context, {
  required List<NoteFolder> folders,
  required int count,
  String? currentFolderId,
  bool sharesFolder = true,
}) {
  final l10n = L10n.of(context);
  final byId = {for (final f in folders) f.id: f};
  // Parents before their children, so "A / B" follows "A".
  final ordered = [
    for (final top in folders.where((f) => !byId.containsKey(f.parentId))) ...[
      top,
      ...folders.where((f) => f.parentId == top.id),
    ],
  ];
  return showWpDialog<NoteFolderMoveTarget>(
    context: context,
    title: l10n.notesMoveToFolderTitle(count),
    content: Builder(
      builder: (context) {
        void pick(NoteFolderMoveTarget target) =>
            Navigator.of(context).pop(target);
        return Wrap(
          spacing: WpSpacing.xs,
          runSpacing: WpSpacing.xxs,
          children: [
            WpFilterChip(
              testId: 'notes-move-target-none',
              label: l10n.notesFolderNone,
              icon: LucideIcons.layoutList,
              isActive: sharesFolder && currentFolderId == null,
              onTap: () => pick(const NoteFolderMoveTarget(null)),
            ),
            for (final f in ordered)
              WpFilterChip(
                testId: 'notes-move-target-${f.id}',
                label: noteFolderPath(f, byId),
                icon: LucideIcons.folder,
                isActive: sharesFolder && currentFolderId == f.id,
                onTap: () => pick(NoteFolderMoveTarget(f.id)),
              ),
            WpFilterChip(
              testId: 'notes-move-target-new',
              label: l10n.notesFolderNewEllipsis,
              icon: LucideIcons.folderPlus,
              isActive: false,
              onTap: () => pick(const NoteFolderMoveTarget.createNew()),
            ),
          ],
        );
      },
    ),
    actions: [
      WpDialogAction(
        label: l10n.actionCancel,
        testId: 'notes-move-cancel',
        role: WpDialogActionRole.cancel,
      ),
    ],
  );
}
