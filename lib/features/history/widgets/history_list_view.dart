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
    required this.selectedId,
    required this.onEntryTap,
    required this.onCopy,
    required this.onPin,
    required this.onDelete,
    this.onDuplicate,
    required this.multiSelectMode,
    required this.selectedIds,
    required this.isTrashView,
    this.focusedId,
    this.onTagTap,
  });

  final List<DateGroup> groups;
  final String? selectedId;
  final ValueChanged<HistoryEntry> onEntryTap;
  final ValueChanged<HistoryEntry> onCopy;
  final ValueChanged<HistoryEntry> onPin;
  final ValueChanged<HistoryEntry> onDelete;
  final ValueChanged<HistoryEntry>? onDuplicate;
  final bool multiSelectMode;
  final Set<String> selectedIds;
  final bool isTrashView;
  final String? focusedId;
  final void Function(String tag)? onTagTap;

  /// Flattened index: each element is either a date header or an entry row.
  late final List<HistoryFlatItem> _flatItems = buildHistoryFlatItems(groups);

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return ListView.builder(
      // The list owns the horizontal page inset (rows and date headers carry
      // none), so its left/right edge lands exactly on the search/filter
      // bar's `xl` inset above it — same arrangement as NotesListView and
      // WpSearchableListPage. History used to be the one area that broke it:
      // the bar sat at 24 while its rows sat at 8 (ticket 03, point 5).
      padding: const EdgeInsets.fromLTRB(
        WpSpacing.xl,
        WpSpacing.xs,
        WpSpacing.xl,
        WpSpacing.xxl,
      ),
      itemCount: _flatItems.length,
      itemBuilder: (_, i) {
        final item = _flatItems[i];
        if (item.headerLabel != null) {
          return HistoryDateHeader(
            label: resolveDateLabel(item.headerLabel!, l10n),
          );
        }
        final entry = item.entry!;
        // loam-ignore: a11y-interactive-semantics – semantics provided in _HistoryEntryRowState.build
        return HistoryEntryRow(
          key: ValueKey(entry.id),
          entry: entry,
          isSelected: multiSelectMode
              ? selectedIds.contains(entry.id)
              : entry.id == selectedId,
          isFocused: !multiSelectMode && entry.id == focusedId,
          onTap: () => onEntryTap(entry),
          onCopy: () => onCopy(entry),
          onPin: () => onPin(entry),
          onDelete: () => onDelete(entry),
          onDuplicate: onDuplicate != null ? () => onDuplicate!(entry) : null,
          multiSelectMode: multiSelectMode,
          isChecked: selectedIds.contains(entry.id),
          isTrashView: isTrashView,
          onTagTap: onTagTap,
        );
      },
    );
  }
}
