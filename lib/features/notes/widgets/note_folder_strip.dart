/// The folder row above the notes list (#659, ADR 0034). Shown only once a
/// folder exists, so the flat list stays the default: "All notes", the
/// top-level folders, and the subfolders of the chosen one in a second row.
///
/// Every chip is a focus stop; the arrow keys move between them, and each
/// chip tells a screen reader its level and note count. The folder actions
/// (new subfolder, rename, delete) sit in the "…" button for the chosen
/// folder and in a chip's context menu, so they never need a mouse.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/data/database.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/views/smart_view.dart';
import '../../../core/views/smart_view_providers.dart';
import '../../../widgets/wp_context_menu.dart';
import '../../../widgets/wp_filter_chip.dart';
import '../../../widgets/wp_icon_button.dart';
import '../data/note_folder_tree.dart';
import '../data/providers.dart';

class NoteFolderStrip extends ConsumerWidget {
  const NoteFolderStrip({
    super.key,
    required this.onShow,
    required this.onCreate,
    required this.onRename,
    required this.onDelete,
  });

  /// Shows [folderId], or all notes when null.
  final ValueChanged<String?> onShow;

  /// Creates a folder under [parentId] (top level when null).
  final ValueChanged<String?> onCreate;
  final ValueChanged<NoteFolder> onRename;
  final ValueChanged<NoteFolder> onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final folders = ref.watch(noteFoldersProvider).value ?? const [];
    if (folders.isEmpty) return const SizedBox.shrink();
    final byId = ref.watch(noteFoldersByIdProvider);
    final tree = buildNoteFolderTree(folders);
    final counts = noteCountsByFolder(
      ref.watch(notesProvider).value ?? const <Note>[],
      byId,
    );
    final viewShown =
        ref.watch(shownSmartViewProvider(SmartViewScope.notes)) != null;
    final shownId = viewShown ? null : ref.watch(shownNoteFolderIdProvider);
    final shown = shownId == null ? null : byId[shownId];
    // The second row belongs to the chosen top-level folder, or to the
    // parent of the chosen subfolder.
    final openTopId = shown == null
        ? null
        : (shown.parentId != null && byId.containsKey(shown.parentId)
              ? shown.parentId
              : shown.id);
    final openNode = openTopId == null
        ? null
        : tree.where((n) => n.folder.id == openTopId).firstOrNull;

    List<WpContextMenuEntry> menuFor(NoteFolder folder) => [
      if (canHoldSubfolder(folder.id, byId))
        WpContextMenuEntry(
          key: ValueKey('notes-folder-new-sub-${folder.id}'),
          icon: LucideIcons.folderPlus,
          label: l10n.notesFolderNewSubfolder,
          onSelected: () => onCreate(folder.id),
        ),
      WpContextMenuEntry(
        key: ValueKey('notes-folder-rename-${folder.id}'),
        icon: LucideIcons.pencil,
        label: l10n.notesFolderRename,
        onSelected: () => onRename(folder),
      ),
      WpContextMenuEntry(
        key: ValueKey('notes-folder-delete-${folder.id}'),
        icon: LucideIcons.trash2,
        label: l10n.notesFolderDelete,
        onSelected: () => onDelete(folder),
        destructive: true,
      ),
    ];

    Widget chip(NoteFolder folder, {required int level}) {
      final count = counts[folder.id] ?? 0;
      return GestureDetector(
        onSecondaryTapUp: (details) => unawaited(
          showWpContextMenu(
            context,
            globalPosition: details.globalPosition,
            entries: menuFor(folder),
          ),
        ),
        child: WpFilterChip(
          testId: 'notes-folder-${folder.id}',
          label: folder.name,
          icon: LucideIcons.folder,
          count: count,
          semanticsHint: l10n.notesFolderChipHint(level, count),
          isActive: shownId == folder.id,
          onTap: () => onShow(folder.id),
        ),
      );
    }

    final menuTarget = shown;
    return Shortcuts(
      // Left and right walk the chips, as in a tab row; Tab still leaves.
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.arrowLeft): DirectionalFocusIntent(
          TraversalDirection.left,
        ),
        SingleActivator(LogicalKeyboardKey.arrowRight): DirectionalFocusIntent(
          TraversalDirection.right,
        ),
      },
      child: Semantics(
        container: true,
        identifier: 'notes-folders',
        label: l10n.notesFolders,
        child: Padding(
          padding: const EdgeInsets.only(bottom: WpSpacing.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: WpSpacing.xs,
                runSpacing: WpSpacing.xxs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  WpFilterChip(
                    testId: 'notes-folder-all',
                    label: l10n.notesFolderAll,
                    icon: LucideIcons.layoutList,
                    isActive: !viewShown && shownId == null,
                    onTap: () => onShow(null),
                  ),
                  for (final node in tree) chip(node.folder, level: 1),
                  WpIconButton.ghost(
                    testId: 'notes-folder-add',
                    icon: LucideIcons.folderPlus,
                    tooltip: l10n.notesFolderNew,
                    compact: true,
                    onPressed: () => onCreate(null),
                  ),
                  if (menuTarget != null)
                    Builder(
                      builder: (context) => WpIconButton.ghost(
                        testId: 'notes-folder-menu',
                        icon: LucideIcons.ellipsis,
                        tooltip: l10n.notesFolderMenu,
                        compact: true,
                        onPressed: () {
                          final box = context.findRenderObject()! as RenderBox;
                          unawaited(
                            showWpContextMenu(
                              context,
                              globalPosition: box.localToGlobal(
                                box.size.bottomLeft(Offset.zero),
                              ),
                              entries: menuFor(menuTarget),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
              if (openNode != null && openNode.children.isNotEmpty)
                Padding(
                  padding: const EdgeInsetsDirectional.only(
                    start: WpSpacing.md,
                    top: WpSpacing.xxs,
                  ),
                  child: Wrap(
                    spacing: WpSpacing.xs,
                    runSpacing: WpSpacing.xxs,
                    children: [
                      for (final child in openNode.children)
                        chip(child, level: 2),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
