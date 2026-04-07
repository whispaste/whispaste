import 'package:flutter/material.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../data/database.dart';
import '../data/providers.dart';
import 'history_date_header.dart';
import 'history_helpers.dart';

// ---------------------------------------------------------------------------
// Compact view — dense power-user list
// ---------------------------------------------------------------------------

class HistoryCompactView extends StatelessWidget {
  const HistoryCompactView({
    super.key,
    required this.groups,
    required this.isDark,
    required this.selectedId,
    required this.onEntryTap,
    required this.multiSelectMode,
    required this.selectedIds,
  });

  final List<DateGroup> groups;
  final bool isDark;
  final String? selectedId;
  final ValueChanged<HistoryEntry> onEntryTap;
  final bool multiSelectMode;
  final Set<String> selectedIds;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final items = <Widget>[];
    for (final group in groups) {
      items.add(HistoryCompactDateHeader(label: resolveDateLabel(group.labelKey, l10n), isDark: isDark));
      for (final entry in group.entries) {
        items.add(
          HistoryCompactRow(
            entry: entry,
            isDark: isDark,
            isSelected: multiSelectMode
                ? selectedIds.contains(entry.id)
                : entry.id == selectedId,
            onTap: () => onEntryTap(entry),
            multiSelectMode: multiSelectMode,
            isChecked: selectedIds.contains(entry.id),
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

// ---------------------------------------------------------------------------
// Compact row — single-line dense entry
// ---------------------------------------------------------------------------

class HistoryCompactRow extends StatefulWidget {
  const HistoryCompactRow({
    super.key,
    required this.entry,
    required this.isDark,
    required this.isSelected,
    required this.onTap,
    this.multiSelectMode = false,
    this.isChecked = false,
  });

  final HistoryEntry entry;
  final bool isDark;
  final bool isSelected;
  final VoidCallback onTap;
  final bool multiSelectMode;
  final bool isChecked;

  @override
  State<HistoryCompactRow> createState() => _HistoryCompactRowState();
}

class _HistoryCompactRowState extends State<HistoryCompactRow> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final textPrimary =
        isDark ? WpColorsDark.textPrimary : WpColorsLight.textPrimary;
    final textMuted =
        isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
    final accent = isDark ? WpColorsDark.accent : WpColorsLight.accent;

    final Color bg;
    if (widget.isSelected) {
      bg = isDark ? WpColorsDark.accentSubtle : WpColorsLight.accentSubtle;
    } else if (_isHovered) {
      bg = isDark ? WpColorsDark.hover : WpColorsLight.hover;
    } else {
      bg = isDark ? WpColorsDark.hoverTransparent : WpColorsLight.hoverTransparent;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: _isHovered ? WpMotion.hoverIn : WpMotion.hoverOut,
          curve: WpMotion.defaultCurve,
          margin: const EdgeInsets.symmetric(horizontal: WpSpacing.xs),
          padding: const EdgeInsets.symmetric(
            horizontal: WpSpacing.sm,
            vertical: 4,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: WpRadius.borderSm,
          ),
          child: Row(
            children: [
              // Multi-select checkbox
              if (widget.multiSelectMode)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: Checkbox(
                      value: widget.isChecked,
                      onChanged: (_) => widget.onTap(),
                      activeColor: accent,
                      side: BorderSide(
                        color: isDark
                            ? WpColorsDark.textMuted
                            : WpColorsLight.textMuted,
                      ),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              // Pin indicator
              if (widget.entry.pinned)
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                  ),
                ),
              // Title
              Expanded(
                child: Text(
                  widget.entry.title.isNotEmpty
                      ? widget.entry.title
                      : L10n.of(context).historyUntitledRecording,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: WpSpacing.sm),
              // Duration
              Text(
                formatHistoryDuration(widget.entry.durationSec),
                style: TextStyle(fontSize: 11, color: textMuted),
              ),
              // Language
              if (widget.entry.language.isNotEmpty) ...[
                const SizedBox(width: WpSpacing.sm),
                Text(
                  widget.entry.language.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    color: textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
              const SizedBox(width: WpSpacing.sm),
              // Time
              Text(
                formatHistoryTime(widget.entry.timestamp),
                style: TextStyle(fontSize: 11, color: textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
