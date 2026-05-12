import 'dart:convert';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import 'package:whispaste/core/data/database.dart';
import 'highlighted_text.dart';
import 'history_helpers.dart';
import 'history_row_action.dart';

/// Whether the current platform uses touch as primary input.
bool get _isTouchPlatform {
  final p = defaultTargetPlatform;
  return p == TargetPlatform.android || p == TargetPlatform.iOS;
}

// ---------------------------------------------------------------------------
// History entry row — WhatsApp/ChatGPT/Discord-inspired
// ---------------------------------------------------------------------------

class HistoryEntryRow extends StatefulWidget {
  const HistoryEntryRow({
    super.key,
    required this.entry,
    required this.isDark,
    required this.isSelected,
    required this.onTap,
    required this.onCopy,
    required this.onPin,
    required this.onDelete,
    this.multiSelectMode = false,
    this.isChecked = false,
    this.isTrashView = false,
    this.isFocused = false,
    this.onTagTap,
  });

  final HistoryEntry entry;
  final bool isDark;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onCopy;
  final VoidCallback onPin;
  final VoidCallback onDelete;
  final bool multiSelectMode;
  final bool isChecked;
  final bool isTrashView;
  final bool isFocused;
  final void Function(String tag)? onTagTap;

  @override
  State<HistoryEntryRow> createState() => _HistoryEntryRowState();
}

class _HistoryEntryRowState extends State<HistoryEntryRow> {
  bool _isHovered = false;

  String get _timeLabel {
    final t = widget.entry.timestamp;
    return '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
  }

  String get _durationLabel {
    final secs = widget.entry.durationSec.round();
    if (secs < 60) return '${secs}s';
    final mins = secs ~/ 60;
    final rem = secs % 60;
    return rem > 0 ? '${mins}m ${rem}s' : '${mins}m';
  }

  int get _wordCount {
    final t = widget.entry.content.trim();
    if (t.isEmpty) return 0;
    return t.split(RegExp(r'\s+')).length;
  }

  List<String> get _entryTags {
    final raw = widget.entry.tags.trim();
    if (raw == '[]' || raw.isEmpty) return const [];
    try {
      return List<String>.from(jsonDecode(raw) as List);
    } catch (_) {
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final l10n = L10n.of(context);
    final avatarCol = historyAvatarColor(widget.entry, isDark);

    // Row background
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

    final textPrimary = isDark
        ? WpColorsDark.textPrimary
        : WpColorsLight.textPrimary;
    final textSecondary = isDark
        ? WpColorsDark.textSecondary
        : WpColorsLight.textSecondary;
    final textMuted = isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
    final accent = isDark ? WpColorsDark.accent : WpColorsLight.accent;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Stack(
          children: [
            // Main content
            AnimatedContainer(
              duration: _isHovered ? WpMotion.hoverIn : WpMotion.hoverOut,
              curve: WpMotion.defaultCurve,
              margin: const EdgeInsets.symmetric(
                horizontal: WpSpacing.xs,
                vertical: 1,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: WpSpacing.sm,
                vertical: WpSpacing.md,
              ),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: WpRadius.borderMd,
                // Use uniform border for selected state (compatible with borderRadius)
                border: widget.isSelected
                    ? Border.all(color: accent, width: 2)
                    : widget.isFocused
                    ? Border.all(
                        color: accent.withValues(alpha: 0.5),
                        width: 1.5,
                      )
                    : null,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Multi-select checkbox
                  if (widget.multiSelectMode)
                    Padding(
                      padding: const EdgeInsets.only(
                        right: WpSpacing.xs,
                        top: 10,
                      ),
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: Checkbox(
                          value: widget.isChecked,
                          onChanged: (_) => widget.onTap(),
                          activeColor: accent,
                          side: BorderSide(
                            color: isDark
                                ? WpColorsDark.textMuted
                                : WpColorsLight.textMuted,
                          ),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ),
                  // Avatar — colored circle with content-type icon
                  HistoryEntryAvatar(
                    color: avatarCol,
                    icon: historyAvatarIcon(widget.entry),
                    isPinned: widget.entry.pinned,
                    isDark: isDark,
                    size: 42,
                  ),
                  const SizedBox(width: WpSpacing.sm),
                  // Content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Row 1: Title + time label
                        Row(
                          children: [
                            Expanded(
                              child: HighlightedText(
                                text: widget.entry.title.isNotEmpty
                                    ? widget.entry.title
                                    : l10n.historyUntitledRecording,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                isDark: isDark,
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w600,
                                  color: textPrimary,
                                ),
                              ),
                            ),
                            // Time label (fades out on hover)
                            AnimatedOpacity(
                              duration: _isHovered
                                  ? WpMotion.fast
                                  : WpMotion.hoverOut,
                              opacity: _isHovered ? 0.0 : 1.0,
                              child: Text(
                                _timeLabel,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: textMuted,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        // Row 2: Content preview — two lines for more context
                        HighlightedText(
                          text: widget.entry.content,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          isDark: isDark,
                          style: TextStyle(
                            fontSize: 14,
                            color: textSecondary,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 4),
                        // Row 3: Subtle inline metadata (duration + language)
                        Row(
                          children: [
                            Icon(
                              LucideIcons.clock,
                              size: WpIconSize.xs,
                              color: textMuted,
                            ),
                            const SizedBox(width: 3),
                            Flexible(
                              child: Text(
                                _durationLabel,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: textMuted,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (_wordCount > 0) ...[
                              const SizedBox(width: WpSpacing.xs),
                              Text(
                                '· ~$_wordCount w',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: textMuted,
                                ),
                              ),
                            ],
                            if (widget.entry.language.isNotEmpty) ...[
                              const SizedBox(width: WpSpacing.xs),
                              Text(
                                '·',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: textMuted,
                                ),
                              ),
                              const SizedBox(width: WpSpacing.xs),
                              Flexible(
                                child: Text(
                                  widget.entry.language.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: textMuted,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                            if (!widget.entry.isLocal) ...[
                              const SizedBox(width: WpSpacing.xs),
                              Text(
                                '·',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: textMuted,
                                ),
                              ),
                              const SizedBox(width: WpSpacing.xs),
                              Icon(
                                LucideIcons.cloud,
                                size: WpIconSize.xs,
                                color: textMuted,
                              ),
                            ],
                          ],
                        ),
                        // Tag chips — only rendered when entry has tags
                        if (_entryTags.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Wrap(
                            spacing: 4,
                            runSpacing: 2,
                            children: [
                              for (final tag in _entryTags.take(3))
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => widget.onTagTap?.call(tag),
                                  child: MouseRegion(
                                    cursor: widget.onTagTap != null
                                        ? SystemMouseCursors.click
                                        : MouseCursor.defer,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        color: accent.withValues(
                                          alpha: isDark ? 0.12 : 0.10,
                                        ),
                                        borderRadius: WpRadius.borderSm,
                                      ),
                                      child: Text(
                                        '#$tag',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: accent.withValues(alpha: 0.9),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              if (_entryTags.length > 3)
                                Text(
                                  '+${_entryTags.length - 3}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: textMuted,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Quick action buttons — visible on hover/focus (desktop) or always (touch)
            if ((_isHovered || _isTouchPlatform || widget.isFocused) &&
                !widget.multiSelectMode)
              Positioned(
                top: 6,
                right: WpSpacing.xs + WpSpacing.sm,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    HistoryRowAction(
                      icon: LucideIcons.copy,
                      tooltip: l10n.historyCopyText,
                      isDark: isDark,
                      onTap: widget.onCopy,
                    ),
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
                    HistoryRowAction(
                      icon: LucideIcons.trash2,
                      tooltip: l10n.actionDelete,
                      isDark: isDark,
                      onTap: widget.onDelete,
                      isDestructive: true,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
