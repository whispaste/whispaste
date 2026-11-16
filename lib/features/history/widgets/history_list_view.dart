import 'package:flutter/material.dart';

import '../../../core/l10n/generated/app_localizations.dart';

import 'package:whispaste/core/data/database.dart';

import '../data/providers.dart';
import 'history_date_header.dart';
import 'history_helpers.dart';
import 'history_list_tile.dart';
import '../../../widgets/wp_collection_list_pane.dart';

// ---------------------------------------------------------------------------
// Entry list with date groups
// ---------------------------------------------------------------------------

class HistoryEntryList extends StatelessWidget {
  const HistoryEntryList({
    super.key,
    this.leading,
    required this.groups,
    required this.selectedId,
    required this.onEntryTap,
    required this.onCopy,
    required this.onPin,
    required this.onDelete,
    this.onDuplicate,
    required this.multiSelectMode,
    required this.selectedIds,
    required this.isTrashView,
    this.onRestore,
    this.focusedId,
    this.onTagTap,
  });

  final List<DateGroup> groups;

  /// Shown above the first row, inside the same scroll owner.
  final Widget? leading;
  final String? selectedId;
  final ValueChanged<HistoryEntry> onEntryTap;
  final ValueChanged<HistoryEntry> onCopy;
  final ValueChanged<HistoryEntry> onPin;
  final ValueChanged<HistoryEntry> onDelete;
  final ValueChanged<HistoryEntry>? onDuplicate;
  final bool multiSelectMode;
  final Set<String> selectedIds;
  final bool isTrashView;
  final ValueChanged<HistoryEntry>? onRestore;
  final String? focusedId;
  final void Function(String tag)? onTagTap;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return WpCollectionListPane<HistoryEntry>(
      storageKey: 'history-scroll-list',
      copyTargetPrefix: 'history',
      leading: leading,
      focusedId: focusedId,
      rows: historyCollectionRows(
        groups,
        (labelKey) =>
            HistoryDateHeader(label: resolveDateLabel(labelKey, l10n)),
      ),
      itemBuilder: (_, entry) => HistoryEntryRow(
        key: ValueKey(entry.id),
        entry: entry,
        isSelected: multiSelectMode
            ? selectedIds.contains(entry.id)
            : entry.id == selectedId,
        isFocused: !multiSelectMode && entry.id == focusedId,
        // No selection means no detail pane beside the list: the overview.
        inSplitView: selectedId != null,
        onTap: () => onEntryTap(entry),
        onCopy: () => onCopy(entry),
        onPin: () => onPin(entry),
        onDelete: () => onDelete(entry),
        onDuplicate: onDuplicate != null ? () => onDuplicate!(entry) : null,
        multiSelectMode: multiSelectMode,
        isChecked: selectedIds.contains(entry.id),
        isTrashView: isTrashView,
        onRestore: onRestore != null ? () => onRestore!(entry) : null,
        onTagTap: onTagTap,
      ),
    );
  }
}
