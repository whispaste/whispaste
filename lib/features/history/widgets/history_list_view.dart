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
  HistoryEntryList({
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
    this.onTagTap,
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
  final void Function(String tag)? onTagTap;

  /// Flattened index: each element is either a date header or an entry row.
  late final List<_FlatItem> _flatItems = _buildFlatItems();

  List<_FlatItem> _buildFlatItems() {
    final result = <_FlatItem>[];
    for (final group in groups) {
      result.add(_FlatItem.header(group.labelKey));
      for (final entry in group.entries) {
        result.add(_FlatItem.entry(entry));
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return ListView.builder(
      padding: const EdgeInsets.only(
        top: WpSpacing.xs,
        bottom: WpSpacing.xxl,
      ),
      itemCount: _flatItems.length,
      itemBuilder: (_, i) {
        final item = _flatItems[i];
        if (item.headerLabel != null) {
          return HistoryDateHeader(
            label: resolveDateLabel(item.headerLabel!, l10n),
            isDark: isDark,
          );
        }
        final entry = item.entry!;
        return HistoryEntryRow(
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
          onTagTap: onTagTap,
        );
      },
    );
  }
}

/// Lightweight union for flattened header/entry items (avoids pre-building
/// widgets — the actual widget is created lazily inside [ListView.builder]).
class _FlatItem {
  const _FlatItem.header(this.headerLabel) : entry = null;
  const _FlatItem.entry(this.entry) : headerLabel = null;

  final String? headerLabel;
  final HistoryEntry? entry;
}