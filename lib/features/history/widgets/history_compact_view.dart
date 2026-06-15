import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
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
    required this.isDark,
    required this.selectedId,
    required this.onEntryTap,
    required this.multiSelectMode,
    required this.selectedIds,
    this.focusedId,
  });

  final List<DateGroup> groups;
  final bool isDark;
  final String? selectedId;
  final ValueChanged<HistoryEntry> onEntryTap;
  final bool multiSelectMode;
  final Set<String> selectedIds;
  final String? focusedId;

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
      padding: const EdgeInsets.only(top: WpSpacing.xs, bottom: WpSpacing.xxl),
      itemCount: _flatItems.length,
      itemBuilder: (_, i) {
        final item = _flatItems[i];
        if (item.headerLabel != null) {
          return HistoryCompactDateHeader(
            label: resolveDateLabel(item.headerLabel!, l10n),
            isDark: isDark,
          );
        }
        final entry = item.entry!;
        // loam-ignore: a11y-interactive-semantics – semantics provided in _HistoryCompactRowState.build
        return HistoryCompactRow(
          entry: entry,
          isDark: isDark,
          isSelected: multiSelectMode
              ? selectedIds.contains(entry.id)
              : entry.id == selectedId,
          isFocused: !multiSelectMode && entry.id == focusedId,
          onTap: () => onEntryTap(entry),
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
    required this.isDark,
    required this.isSelected,
    required this.onTap,
    this.multiSelectMode = false,
    this.isChecked = false,
    this.isFocused = false,
  });

  final HistoryEntry entry;
  final bool isDark;
  final bool isSelected;
  final VoidCallback onTap;
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
    final isDark = widget.isDark;
    final textPrimary = isDark
        ? WpColorsDark.textPrimary
        : WpColorsLight.textPrimary;
    final textMuted = isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
    final accent = isDark ? WpColorsDark.accent : WpColorsLight.accent;

    final Color bg;
    if (widget.isSelected) {
      bg = isDark ? WpColorsDark.accentSubtle : WpColorsLight.accentSubtle;
    } else if (widget.isFocused) {
      bg = isDark ? WpColorsDark.hover : WpColorsLight.hover;
    } else if (_isHovered) {
      bg = isDark ? WpColorsDark.hover : WpColorsLight.hover;
    } else {
      bg = isDark
          ? WpColorsDark.hoverTransparent
          : WpColorsLight.hoverTransparent;
    }

    final l10n = L10n.of(context);
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
            margin: const EdgeInsets.symmetric(horizontal: WpSpacing.xs),
            padding: const EdgeInsets.symmetric(
              horizontal: WpSpacing.sm,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: WpRadius.borderSm,
              border: widget.isFocused
                  ? Border.all(color: accent.withValues(alpha: 0.5), width: 1.5)
                  : null,
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
                // Favorite indicator
                if (widget.entry.pinned)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FaIcon(
                      FontAwesomeIcons.solidStar,
                      size: 10,
                      color: Colors.amber.shade600,
                    ),
                  ),
                // Title
                Expanded(
                  child: HighlightedText(
                    text: widget.entry.title.isNotEmpty
                        ? widget.entry.title
                        : l10n.historyUntitledRecording,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    isDark: isDark,
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
      ),
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
