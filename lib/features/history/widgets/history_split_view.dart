import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import 'package:whispaste/core/data/database.dart';
import '../../../services/history/history_exporter.dart' as history_exporter;
import '../../../widgets/wp_split_view.dart';
import '../data/providers.dart';
import 'history_card_view.dart';
import 'history_compact_view.dart';
import 'history_detail_panel.dart';
import 'history_helpers.dart';
import 'history_list_view.dart';

// ---------------------------------------------------------------------------
// Split-View layout
// ---------------------------------------------------------------------------

/// History's master/detail area — the geometry, the divider and the
/// entry-to-entry cross-fade all live in [WpSplitView]; what stays here is the
/// history-specific content of the two columns, above all the view-mode
/// switcher the notes area deliberately does not have.
class HistorySplitView extends StatelessWidget {
  const HistorySplitView({
    super.key,
    required this.groups,
    required this.viewMode,
    required this.selectedEntry,
    required this.onEntryTap,
    required this.onCopy,
    required this.onPin,
    required this.onDelete,
    required this.onArchive,
    required this.onRestore,
    required this.onCloseDetail,
    required this.multiSelectMode,
    required this.selectedIds,
    required this.isTrashView,
    required this.isArchiveView,
    this.onDuplicate,
    this.onCopyMarkdown,
    this.focusedId,
    this.onTagTap,
    this.exportFn = history_exporter.exportEntries,
  });

  final List<DateGroup> groups;
  final HistoryViewMode viewMode;
  final HistoryEntry? selectedEntry;
  final ValueChanged<HistoryEntry> onEntryTap;
  final ValueChanged<HistoryEntry> onCopy;
  final ValueChanged<HistoryEntry> onPin;
  final ValueChanged<HistoryEntry> onDelete;
  final ValueChanged<HistoryEntry> onArchive;
  final ValueChanged<HistoryEntry> onRestore;
  final VoidCallback onCloseDetail;
  final bool multiSelectMode;
  final Set<String> selectedIds;
  final bool isTrashView;
  final bool isArchiveView;
  final ValueChanged<HistoryEntry>? onDuplicate;
  final ValueChanged<HistoryEntry>? onCopyMarkdown;
  final String? focusedId;
  final void Function(String tag)? onTagTap;

  /// Forwarded to [HistoryDetailPanel] so the overflow "Export…" item routes
  /// through the same seam as the multi-select toolbar. Defaults to the
  /// production [history_exporter.exportEntries]; widget tests inject a fake.
  final HistoryDetailPanelExportFn exportFn;

  Widget _buildListBody(BuildContext context, String? selectedId) {
    final Widget body;
    switch (viewMode) {
      case HistoryViewMode.list:
        body = HistoryEntryList(
          key: const ValueKey('view-list'),
          groups: groups,
          selectedId: selectedId,
          focusedId: focusedId,
          onEntryTap: onEntryTap,
          onCopy: onCopy,
          onPin: onPin,
          onDelete: onDelete,
          multiSelectMode: multiSelectMode,
          selectedIds: selectedIds,
          isTrashView: isTrashView,
          onTagTap: onTagTap,
        );
      case HistoryViewMode.cards:
        body = HistoryCardView(
          key: const ValueKey('view-cards'),
          groups: groups,
          selectedId: selectedId,
          focusedId: focusedId,
          onEntryTap: onEntryTap,
          onCopy: onCopy,
          onPin: onPin,
          onDelete: onDelete,
          multiSelectMode: multiSelectMode,
          selectedIds: selectedIds,
        );
      case HistoryViewMode.compact:
        body = HistoryCompactView(
          key: const ValueKey('view-compact'),
          groups: groups,
          selectedId: selectedId,
          focusedId: focusedId,
          onEntryTap: onEntryTap,
          onCopy: onCopy,
          onPin: onPin,
          onDelete: onDelete,
          multiSelectMode: multiSelectMode,
          selectedIds: selectedIds,
        );
    }
    // Stays here, not in WpSplitView: this fade covers the *view-mode*
    // switch, which only history has (CONTEXT.md §5.9).
    return AnimatedSwitcher(
      duration: WpMotion.durationFor(context, WpMotion.normal),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: body,
    );
  }

  Widget _buildDetailPanel(BuildContext context, HistoryEntry entry) {
    return HistoryDetailPanel(
      entry: entry,
      isTrashView: isTrashView,
      isArchiveView: isArchiveView,
      onClose: onCloseDetail,
      onCopy: () => onCopy(entry),
      onPin: () => onPin(entry),
      onDelete: () => onDelete(entry),
      onArchive: () => onArchive(entry),
      onRestore: () => onRestore(entry),
      onDuplicate: onDuplicate == null ? null : () => onDuplicate!(entry),
      onCopyMarkdown: onCopyMarkdown == null
          ? null
          : () => onCopyMarkdown!(entry),
      exportFn: exportFn,
    );
  }

  @override
  Widget build(BuildContext context) {
    return WpSplitView<HistoryEntry>(
      selectedItem: selectedEntry,
      idOf: (entry) => entry.id,
      listBuilder: _buildListBody,
      detailBuilder: _buildDetailPanel,
    );
  }
}
