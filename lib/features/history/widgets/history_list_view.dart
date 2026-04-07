import 'package:flutter/material.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/tokens.dart';
import 'package:whispaste/core/data/database.dart';
import '../data/providers.dart';
import 'history_date_header.dart';
import 'history_helpers.dart';
import 'history_list_tile.dart';

// ---------------------------------------------------------------------------
// Entry list with date groups
// ---------------------------------------------------------------------------

class HistoryEntryList extends StatelessWidget {
  const HistoryEntryList({
    super.key,
    required this.groups,
    required this.isDark,
    required this.selectedId,
    required this.onEntryTap,
    required this.onCopy,
    required this.onPin,
    required this.onDelete,
    required this.multiSelectMode,
    required this.selectedIds,
    required this.isTrashView,
    this.focusedId,
  });

  final List<DateGroup> groups;
  final bool isDark;
  final String? selectedId;
  final ValueChanged<HistoryEntry> onEntryTap;
  final ValueChanged<HistoryEntry> onCopy;
  final ValueChanged<HistoryEntry> onPin;
  final ValueChanged<HistoryEntry> onDelete;
  final bool multiSelectMode;
  final Set<String> selectedIds;
  final bool isTrashView;
  final String? focusedId;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final items = <Widget>[];

    for (final group in groups) {
      items.add(HistoryDateHeader(label: resolveDateLabel(group.labelKey, l10n), isDark: isDark));
      for (final entry in group.entries) {
        items.add(
          HistoryEntryRow(
            entry: entry,
            isDark: isDark,
            isSelected: multiSelectMode
                ? selectedIds.contains(entry.id)
                : entry.id == selectedId,
            isFocused: !multiSelectMode && entry.id == focusedId,
            onTap: () => onEntryTap(entry),
            onCopy: () => onCopy(entry),
            onPin: () => onPin(entry),
            onDelete: () => onDelete(entry),
            multiSelectMode: multiSelectMode,
            isChecked: selectedIds.contains(entry.id),
            isTrashView: isTrashView,
          ),
        );
      }
    }

    return ListView.builder(
      padding: const EdgeInsets.only(
        top: WpSpacing.xs,
        bottom: WpSpacing.xxl,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) => items[i],
    );
  }
}
