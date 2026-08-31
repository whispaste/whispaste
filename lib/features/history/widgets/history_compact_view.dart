import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/wp_row_action.dart';
import '../../../widgets/wp_row_checkbox.dart';
import 'package:whispaste/core/data/database.dart';
import '../data/providers.dart';
import 'highlighted_text.dart';
import 'history_date_header.dart';
import 'history_helpers.dart';

// ---------------------------------------------------------------------------
// Compact view — dense power-user list
// ---------------------------------------------------------------------------

class HistoryCompactView extends StatelessWidget {
  HistoryCompactView({
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
    this.focusedId,
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
  final String? focusedId;

  /// Flattened index: each element is either a date header or an entry row.
  late final List<HistoryFlatItem> _flatItems = buildHistoryFlatItems(groups);

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return ListView.builder(
      // The list owns the horizontal page inset — see HistoryEntryList
      // (ticket 03, point 5): all three view modes line up with the bar.
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
          return HistoryCompactDateHeader(
            label: resolveDateLabel(item.headerLabel!, l10n),
          );
        }
        final entry = item.entry!;
        // loam-ignore: a11y-interactive-semantics – semantics provided in _HistoryCompactRowState.build
        return HistoryCompactRow(
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
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Compact row — single-line dense entry
// ---------------------------------------------------------------------------

class HistoryCompactRow extends StatefulWidget {
  const HistoryCompactRow({
    super.key,
    required this.entry,
    required this.isSelected,
    required this.onTap,
    required this.onCopy,
    required this.onPin,
    required this.onDelete,
    this.onDuplicate,
    this.multiSelectMode = false,
    this.isChecked = false,
    this.isFocused = false,
  });

  final HistoryEntry entry;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onCopy;
  final VoidCallback onPin;
  final VoidCallback onDelete;
  final VoidCallback? onDuplicate;
  final bool multiSelectMode;
  final bool isChecked;
  final bool isFocused;

  @override
  State<HistoryCompactRow> createState() => _HistoryCompactRowState();
}

class _HistoryCompactRowState extends State<HistoryCompactRow> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    const textPrimary = WpColors.textPrimary;
    const textMuted = WpColors.textMuted;
    const accent = WpColors.accent;

    final Color bg;
    if (widget.isSelected) {
      bg = WpColors.accentSubtle;
    } else if (widget.isFocused) {
      bg = WpColors.hover;
    } else if (_isHovered) {
      bg = WpColors.hover;
    } else {
      bg = WpColors.hoverTransparent;
    }

    final l10n = L10n.of(context);
    final semanticLabel = widget.entry.title.isNotEmpty
        ? widget.entry.title
        : l10n.historyUntitledRecording;

    return Semantics(
      // Group variant of the house idiom — see history_list_tile.dart:134 for
      // the full reasoning; the row holds the same several interactive nodes,
      // so the wrapper keeps `label:` and the rendered title is excluded below.
      label: semanticLabel,
      button: true,
      // Arrow cursor, not detail selection — see history_list_tile.dart.
      selected: widget.multiSelectMode ? widget.isSelected : widget.isFocused,
      focused: widget.isFocused,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: WpMotion.durationFor(
              context,
              _isHovered ? WpMotion.hoverIn : WpMotion.hoverOut,
            ),
            curve: WpMotion.defaultCurve,
            // No horizontal margin — the list owns the page inset (ticket 03,
            // point 5) so the row edge lands on the filter bar's `xl`.
            padding: const EdgeInsets.symmetric(
              horizontal: WpSpacing.sm,
              vertical: WpSpacing.xxs,
            ),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: WpRadius.borderSm,
              // Always present (never null) so AnimatedContainer fades the
              // border's alpha instead of its width — see the matching fix
              // + doc comment in history_list_tile.dart for why a null
              // target reads as a one-frame flash instead of a fade.
              // Light-theme focus ink reduced to 0.45 (matches the list
              // tile's focused stroke) — the dark light-accent #06678A at
              // 0.5 read heavier here than the same alpha does on dark.
              border: widget.isFocused
                  ? Border.all(color: accent.withValues(alpha: 0.5), width: 1.5)
                  : Border.all(color: accent.withValues(alpha: 0), width: 1.5),
            ),
            child: Row(
              children: [
                // Multi-select checkbox
                if (widget.multiSelectMode)
                  Padding(
                    // Off-scale on purpose: compact-view leading-icon gap sits
                    // between xxs (too tight next to the checkbox) and xs (too
                    // loose for this row density).
                    padding: const EdgeInsets.only(right: 6),
                    child: WpRowCheckbox(
                      value: widget.isChecked,
                      onChanged: widget.onTap,
                    ),
                  ),
                // Favorite indicator
                if (widget.entry.pinned)
                  const Padding(
                    // Off-scale on purpose: same compact leading-icon gap as
                    // the checkbox above, keeping star and checkbox aligned.
                    padding: EdgeInsets.only(right: 6),
                    child: FaIcon(
                      FontAwesomeIcons.solidStar,
                      size: 10,
                      color: WpSharedColors.pinnedAccent,
                    ),
                  ),
                // Title
                Expanded(
                  // Duplicate of the wrapper's label — excluded so the row's
                  // title is announced once, not twice. The duration and
                  // language below stay announced.
                  child: ExcludeSemantics(
                    child: HighlightedText(
                      text: widget.entry.title.isNotEmpty
                          ? widget.entry.title
                          : l10n.historyUntitledRecording,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: WpTypography.body,
                        fontWeight: FontWeight.w500,
                        color: textPrimary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: WpSpacing.xs),
                HistoryCompactRowActions(
                  entry: widget.entry,
                  visible:
                      (_isHovered || widget.isFocused) &&
                      !widget.multiSelectMode,
                  onCopy: widget.onCopy,
                  onPin: widget.onPin,
                  onDelete: widget.onDelete,
                  onDuplicate: widget.onDuplicate,
                ),
                const SizedBox(width: WpSpacing.sm),
                // Duration
                Text(
                  formatHistoryDuration(widget.entry.durationSec),
                  style: const TextStyle(
                    fontSize: WpTypography.caption,
                    color: textMuted,
                  ),
                ),
                // Language
                if (widget.entry.language.isNotEmpty) ...[
                  const SizedBox(width: WpSpacing.sm),
                  Text(
                    widget.entry.language.toUpperCase(),
                    style: const TextStyle(
                      fontSize: WpTypography.caption,
                      color: textMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                const SizedBox(width: WpSpacing.sm),
                // Time
                Text(
                  formatHistoryTime(widget.entry.timestamp),
                  style: const TextStyle(
                    fontSize: WpTypography.caption,
                    color: textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Compact row actions — the same three the list and card views offer.
// Switching the view changes the density, not the feature set
// (CONTEXT.md §5.5.5); the compact row keeps the dense variant so it stays
// several times denser than the list row. They sit ahead of the metadata so
// duration/language/time stay anchored and only the flexible title gives way.
//
// Its own widget rather than an inline block: the compact row's build method
// is already at the edge of loam's complexity budget, and the pinned-state
// branching below would push it over.
// ---------------------------------------------------------------------------

class HistoryCompactRowActions extends StatelessWidget {
  const HistoryCompactRowActions({
    super.key,
    required this.entry,
    required this.visible,
    required this.onCopy,
    required this.onPin,
    required this.onDelete,
    this.onDuplicate,
  });

  final HistoryEntry entry;
  final bool visible;
  final VoidCallback onCopy;
  final VoidCallback onPin;
  final VoidCallback onDelete;
  final VoidCallback? onDuplicate;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final pinned = entry.pinned;
    return WpRowActions(
      visible: visible,
      dense: true,
      children: [
        // loam-ignore: a11y-interactive-semantics – semantics provided in _WpRowActionState.build
        WpRowAction(
          icon: LucideIcons.copy,
          tooltip: l10n.historyCopyText,
          onTap: onCopy,
          dense: true,
        ),
        // loam-ignore: a11y-interactive-semantics – semantics provided in _WpRowActionState.build
        WpRowAction(
          faIcon: pinned ? FontAwesomeIcons.solidStar : null,
          icon: pinned ? null : LucideIcons.star,
          activeColor: pinned ? WpSharedColors.pinnedAccent : null,
          tooltip: pinned ? l10n.historyUnpin : l10n.historyPinToTop,
          onTap: onPin,
          dense: true,
        ),
        // loam-ignore: a11y-interactive-semantics – semantics provided in _WpRowActionState.build
        if (onDuplicate case final onDuplicate?)
          WpRowAction(
            icon: LucideIcons.files,
            tooltip: l10n.actionDuplicate,
            onTap: onDuplicate,
            dense: true,
          ),
        WpRowAction(
          icon: LucideIcons.trash2,
          tooltip: l10n.actionDelete,
          onTap: onDelete,
          isDestructive: true,
          dense: true,
        ),
      ],
    );
  }
}
