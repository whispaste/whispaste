import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import 'package:whispaste/core/data/database.dart';
import '../data/providers.dart';
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
        final columns =
            (availableWidth / minCardWidth).floor().clamp(1, 4);
        final cardWidth =
            (availableWidth - gap * (columns - 1)) / columns;

        return ListView(
          padding: const EdgeInsets.only(
            top: WpSpacing.xs,
            bottom: WpSpacing.xxl,
          ),
          children: [
            for (final group in groups) ...[
              HistoryDateHeader(label: resolveDateLabel(group.labelKey, l10n), isDark: isDark),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: sidePad),
                child: Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final entry in group.entries)
                      SizedBox(
                        width: cardWidth,
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
              ),
            ],
          ],
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

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final l10n = L10n.of(context);
    final avatarCol = historyAvatarColor(widget.entry, isDark);
    final accent = isDark ? WpColorsDark.accent : WpColorsLight.accent;
    final textPrimary =
        isDark ? WpColorsDark.textPrimary : WpColorsLight.textPrimary;
    final textSecondary =
        isDark ? WpColorsDark.textSecondary : WpColorsLight.textSecondary;
    final textMuted =
        isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
    final surfaceElevated = isDark
        ? WpColorsDark.surfaceElevated
        : WpColorsLight.surfaceElevated;
    final borderColor = widget.isSelected
        ? accent.withValues(alpha: 0.5)
        : widget.isFocused
            ? accent.withValues(alpha: 0.4)
            : (isDark ? WpColorsDark.borderSubtle : WpColorsLight.borderSubtle);

    return MouseRegion(
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
                    child: Text(
                      widget.entry.title.isNotEmpty
                          ? widget.entry.title
                          : L10n.of(context).historyUntitledRecording,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: textPrimary,
                      ),
                    ),
                  ),
                  // Hover action buttons — constrained to avoid overflow
                  if (_isHovered)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        HistoryRowAction(
                          icon: LucideIcons.copy,
                          tooltip: l10n.historyCopyText,
                          isDark: isDark,
                          onTap: widget.onCopy,
                        ),
                        HistoryRowAction(
                          icon: widget.entry.pinned
                              ? LucideIcons.starOff
                              : LucideIcons.star,
                          tooltip: widget.entry.pinned ? l10n.historyUnpin : l10n.historyPinToTop,
                          isDark: isDark,
                          onTap: widget.onPin,
                        ),
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
                child: Text(
                  widget.entry.content,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
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
                  Icon(LucideIcons.clock, size: WpIconSize.xs, color: textMuted),
                  const SizedBox(width: 3),
                  Text(
                    formatHistoryDuration(widget.entry.durationSec),
                    style: TextStyle(fontSize: 10, color: textMuted),
                  ),
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
                    Icon(LucideIcons.cloud, size: WpIconSize.xs, color: textMuted),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
