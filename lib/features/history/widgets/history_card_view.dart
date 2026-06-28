import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import 'package:whispaste/core/data/database.dart';
import '../data/providers.dart';
import 'highlighted_text.dart';
import 'history_date_header.dart';
import 'history_helpers.dart';
import 'history_row_action.dart';

// ---------------------------------------------------------------------------
// Card view — responsive grid of entry cards
// ---------------------------------------------------------------------------

class HistoryCardView extends StatelessWidget {
  const HistoryCardView({
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
  final String? focusedId;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        const minCardWidth = 280.0;
        const gap = WpSpacing.md;
        const sidePad = WpSpacing.md;
        final availableWidth = constraints.maxWidth - sidePad * 2;
        final columns = (availableWidth / minCardWidth).floor().clamp(1, 4);
        final cardWidth = (availableWidth - gap * (columns - 1)) / columns;

        // Flat list: each group → 1 header + 1 wrap widget
        final flatItems = <_CardFlatItem>[];
        for (final group in groups) {
          flatItems.add(_CardFlatItem.header(group.labelKey));
          flatItems.add(_CardFlatItem.group(group.entries));
        }

        return ListView.builder(
          padding: const EdgeInsets.only(
            top: WpSpacing.xs,
            bottom: WpSpacing.xxl,
          ),
          itemCount: flatItems.length,
          itemBuilder: (_, i) {
            final item = flatItems[i];
            if (item.headerLabel != null) {
              return HistoryDateHeader(
                label: resolveDateLabel(item.headerLabel!, l10n),
                isDark: isDark,
              );
            }
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: sidePad),
              child: Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final entry in item.entries!)
                    SizedBox(
                      width: cardWidth,
                      // loam-ignore: a11y-interactive-semantics – semantics provided in _HistoryEntryCardState.build
                      child: HistoryEntryCard(
                        entry: entry,
                        isDark: isDark,
                        isSelected: entry.id == selectedId,
                        isFocused: entry.id == focusedId,
                        onTap: () => onEntryTap(entry),
                        onCopy: () => onCopy(entry),
                        onPin: () => onPin(entry),
                        onDelete: () => onDelete(entry),
                        multiSelectMode: multiSelectMode,
                        isMultiSelected: selectedIds.contains(entry.id),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Entry card — used in card grid view
// ---------------------------------------------------------------------------

class HistoryEntryCard extends StatefulWidget {
  const HistoryEntryCard({
    super.key,
    required this.entry,
    required this.isDark,
    required this.isSelected,
    required this.onTap,
    required this.onCopy,
    required this.onPin,
    required this.onDelete,
    required this.multiSelectMode,
    required this.isMultiSelected,
    this.isFocused = false,
  });

  final HistoryEntry entry;
  final bool isDark;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onCopy;
  final VoidCallback onPin;
  final VoidCallback onDelete;
  final bool multiSelectMode;
  final bool isMultiSelected;
  final bool isFocused;

  @override
  State<HistoryEntryCard> createState() => _HistoryEntryCardState();
}

class _HistoryEntryCardState extends State<HistoryEntryCard> {
  bool _isHovered = false;

  int get _wordCount {
    final t = widget.entry.content.trim();
    if (t.isEmpty) return 0;
    return t.split(RegExp(r'\s+')).length;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final l10n = L10n.of(context);
    final avatarCol = historyAvatarColor(widget.entry, isDark);
    final accent = isDark ? WpColorsDark.accent : WpColorsLight.accent;
    final textPrimary = isDark
        ? WpColorsDark.textPrimary
        : WpColorsLight.textPrimary;
    final textSecondary = isDark
        ? WpColorsDark.textSecondary
        : WpColorsLight.textSecondary;
    final textMuted = isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
    final surfaceElevated = isDark
        ? WpColorsDark.surfaceElevated
        : WpColorsLight.surfaceElevated;
    final borderColor = widget.isSelected
        ? accent.withValues(alpha: 0.5)
        : widget.isFocused
        ? accent.withValues(alpha: 0.4)
        : (isDark ? WpColorsDark.borderSubtle : WpColorsLight.borderSubtle);

    final semanticLabel = widget.entry.title.isNotEmpty
        ? widget.entry.title
        : l10n.historyUntitledRecording;

    return Semantics(
      label: semanticLabel,
      button: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: _isHovered ? WpMotion.hoverIn : WpMotion.hoverOut,
            curve: WpMotion.defaultCurve,
            height: 180,
            padding: const EdgeInsets.all(WpSpacing.md),
            decoration: BoxDecoration(
              color: surfaceElevated,
              borderRadius: WpRadius.borderMd,
              border: Border.all(color: borderColor),
              boxShadow: _isHovered ? WpShadows.subtle : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row: avatar + title + hover actions
                Row(
                  children: [
                    HistoryEntryAvatar(
                      color: avatarCol,
                      icon: historyAvatarIcon(widget.entry),
                      isPinned: widget.entry.pinned,
                      isDark: isDark,
                      size: 32,
                    ),
                    const SizedBox(width: WpSpacing.xs),
                    Expanded(
                      child: HighlightedText(
                        text: widget.entry.title.isNotEmpty
                            ? widget.entry.title
                            : l10n.historyUntitledRecording,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        isDark: isDark,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: textPrimary,
                        ),
                      ),
                    ),
                    // Action buttons — visible on hover/focus
                    if (_isHovered || widget.isFocused)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // loam-ignore: a11y-interactive-semantics – semantics provided in _HistoryRowActionState.build
                          HistoryRowAction(
                            icon: LucideIcons.copy,
                            tooltip: l10n.historyCopyText,
                            isDark: isDark,
                            onTap: widget.onCopy,
                          ),
                          // loam-ignore: a11y-interactive-semantics – semantics provided in _HistoryRowActionState.build
                          HistoryRowAction(
                            faIcon: widget.entry.pinned
                                ? FontAwesomeIcons.solidStar
                                : null,
                            icon: widget.entry.pinned ? null : LucideIcons.star,
                            activeColor: widget.entry.pinned
                                ? Colors.amber.shade600
                                : null,
                            tooltip: widget.entry.pinned
                                ? l10n.historyUnpin
                                : l10n.historyPinToTop,
                            isDark: isDark,
                            onTap: widget.onPin,
                          ),
                          // loam-ignore: a11y-interactive-semantics – semantics provided in _HistoryRowActionState.build
                          HistoryRowAction(
                            icon: LucideIcons.trash2,
                            tooltip: l10n.actionDelete,
                            isDark: isDark,
                            onTap: widget.onDelete,
                            isDestructive: true,
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: WpSpacing.xs),
                // Content preview (3-4 lines)
                Expanded(
                  child: HighlightedText(
                    text: widget.entry.content,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    isDark: isDark,
                    style: TextStyle(
                      fontSize: 13,
                      color: textSecondary,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: WpSpacing.xs),
                // Bottom metadata
                Row(
                  children: [
                    Icon(
                      LucideIcons.clock,
                      size: WpIconSize.xs,
                      color: textMuted,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      formatHistoryDuration(widget.entry.durationSec),
                      style: TextStyle(fontSize: 10, color: textMuted),
                    ),
                    if (_wordCount > 0) ...[
                      const SizedBox(width: WpSpacing.xs),
                      Text(
                        '· ~$_wordCount w',
                        style: TextStyle(fontSize: 10, color: textMuted),
                      ),
                    ],
                    if (widget.entry.language.isNotEmpty) ...[
                      const SizedBox(width: WpSpacing.xs),
                      Text(
                        '·',
                        style: TextStyle(fontSize: 10, color: textMuted),
                      ),
                      const SizedBox(width: WpSpacing.xs),
                      Text(
                        widget.entry.language.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          color: textMuted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    const Spacer(),
                    if (!widget.entry.isLocal)
                      Icon(
                        LucideIcons.cloud,
                        size: WpIconSize.xs,
                        color: textMuted,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Lightweight union for flattened header / card-group items (avoids eagerly
/// building the full widget list).
class _CardFlatItem {
  const _CardFlatItem.header(this.headerLabel) : entries = null;
  const _CardFlatItem.group(this.entries) : headerLabel = null;

  final String? headerLabel;
  final List<HistoryEntry>? entries;
}
