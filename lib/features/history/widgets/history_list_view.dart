import 'package:flutter/material.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/tokens.dart';
import 'package:whispaste/core/data/database.dart';
import '../data/providers.dart';
import 'history_date_header.dart';
import 'history_focus_reveal.dart';
import 'history_helpers.dart';
import 'history_list_tile.dart';

// ---------------------------------------------------------------------------
// Entry list with date groups
// ---------------------------------------------------------------------------

class HistoryEntryList extends StatefulWidget {
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
    this.onRestore,
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
  final ValueChanged<HistoryEntry>? onRestore;
  final String? focusedId;
  final void Function(String tag)? onTagTap;

  /// Flattened index: each element is either a date header or an entry row.
  late final List<HistoryFlatItem> _flatItems = buildHistoryFlatItems(groups);

  @override
  State<HistoryEntryList> createState() => _HistoryEntryListState();
}

class _HistoryEntryListState extends State<HistoryEntryList> {
  final HistoryFocusReveal _reveal = HistoryFocusReveal();

  @override
  void didUpdateWidget(covariant HistoryEntryList old) {
    super.didUpdateWidget(old);
    if (widget.focusedId != null && widget.focusedId != old.focusedId) {
      _reveal.schedule(widget._flatItems, widget.focusedId);
    }
  }

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return ListView.builder(
      controller: _reveal.scroll,
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
      itemCount: widget._flatItems.length,
      itemBuilder: (_, i) {
        final item = widget._flatItems[i];
        if (item.headerLabel != null) {
          return HistoryDateHeader(
            label: resolveDateLabel(item.headerLabel!, l10n),
          );
        }
        final entry = item.entry!;
        return _reveal.wrap(
          entry.id,
          // loam-ignore: a11y-interactive-semantics – semantics provided in _HistoryEntryRowState.build
          HistoryEntryRow(
            key: ValueKey(entry.id),
            entry: entry,
            isSelected: widget.multiSelectMode
                ? widget.selectedIds.contains(entry.id)
                : entry.id == widget.selectedId,
            isFocused: !widget.multiSelectMode && entry.id == widget.focusedId,
            // No selection means no detail pane beside the list: the overview.
            inSplitView: widget.selectedId != null,
            onTap: () => widget.onEntryTap(entry),
            onCopy: () => widget.onCopy(entry),
            onPin: () => widget.onPin(entry),
            onDelete: () => widget.onDelete(entry),
            onDuplicate: widget.onDuplicate != null
                ? () => widget.onDuplicate!(entry)
                : null,
            multiSelectMode: widget.multiSelectMode,
            isChecked: widget.selectedIds.contains(entry.id),
            isTrashView: widget.isTrashView,
            onRestore: widget.onRestore != null
                ? () => widget.onRestore!(entry)
                : null,
            onTagTap: widget.onTagTap,
          ),
        );
      },
    );
  }
}
