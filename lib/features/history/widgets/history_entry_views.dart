import 'package:flutter/material.dart';

import 'package:whispaste/core/data/database.dart';

import '../../../core/theme/tokens.dart';
import '../data/providers.dart';
import 'history_card_view.dart';
import 'history_compact_view.dart';
import 'history_helpers.dart';
import 'history_list_view.dart';

/// The list column of the history page: one of the three view modes (list,
/// cards, compact), cross-faded on a mode switch. The split around it —
/// geometry, divider, detail — is the shared `WpCollectionSplit`; only this
/// view-mode switcher is history's own (internal-notes §5.9).
class HistoryEntryViews extends StatelessWidget {
  const HistoryEntryViews({
    super.key,
    this.leading,
    required this.groups,
    required this.viewMode,
    required this.selectedId,
    required this.focusedId,
    required this.multiSelectMode,
    required this.selectedIds,
    required this.isTrashView,
    required this.onEntryTap,
    required this.onCopy,
    required this.onPin,
    required this.onDelete,
    required this.onRestore,
    this.onDuplicate,
    this.onTagTap,
  });

  /// Scrolls with the rows as their first item (the import panel).
  final Widget? leading;
  final List<DateGroup> groups;
  final HistoryViewMode viewMode;
  final String? selectedId;
  final String? focusedId;
  final bool multiSelectMode;
  final Set<String> selectedIds;
  final bool isTrashView;
  final ValueChanged<HistoryEntry> onEntryTap;
  final ValueChanged<HistoryEntry> onCopy;
  final ValueChanged<HistoryEntry> onPin;
  final ValueChanged<HistoryEntry> onDelete;
  final ValueChanged<HistoryEntry> onRestore;
  final ValueChanged<HistoryEntry>? onDuplicate;

  /// Only the list mode shows tags.
  final void Function(String tag)? onTagTap;

  @override
  Widget build(BuildContext context) {
    final Widget body = switch (viewMode) {
      HistoryViewMode.list => HistoryEntryList(
        key: const ValueKey('view-list'),
        leading: leading,
        groups: groups,
        selectedId: selectedId,
        focusedId: focusedId,
        onEntryTap: onEntryTap,
        onCopy: onCopy,
        onPin: onPin,
        onDelete: onDelete,
        onDuplicate: onDuplicate,
        multiSelectMode: multiSelectMode,
        selectedIds: selectedIds,
        isTrashView: isTrashView,
        onRestore: onRestore,
        onTagTap: onTagTap,
      ),
      HistoryViewMode.cards => HistoryCardView(
        key: const ValueKey('view-cards'),
        leading: leading,
        groups: groups,
        selectedId: selectedId,
        focusedId: focusedId,
        onEntryTap: onEntryTap,
        onCopy: onCopy,
        onPin: onPin,
        onDelete: onDelete,
        onDuplicate: onDuplicate,
        multiSelectMode: multiSelectMode,
        selectedIds: selectedIds,
        isTrashView: isTrashView,
        onRestore: onRestore,
      ),
      HistoryViewMode.compact => HistoryCompactView(
        key: const ValueKey('view-compact'),
        leading: leading,
        groups: groups,
        selectedId: selectedId,
        focusedId: focusedId,
        onEntryTap: onEntryTap,
        onCopy: onCopy,
        onPin: onPin,
        onDelete: onDelete,
        onDuplicate: onDuplicate,
        multiSelectMode: multiSelectMode,
        selectedIds: selectedIds,
        isTrashView: isTrashView,
        onRestore: onRestore,
      ),
    };
    return AnimatedSwitcher(
      duration: WpMotion.durationFor(context, WpMotion.normal),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: body,
    );
  }
}
