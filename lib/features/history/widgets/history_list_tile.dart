import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/wp_focus_ring.dart';
import 'package:whispaste/core/data/database.dart';
import 'highlighted_text.dart';
import 'history_helpers.dart';
import 'history_row_action.dart';
import '../../../core/utils/word_count.dart';

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

  // Memoized once per `entry` change (initState + didUpdateWidget), not
  // recomputed on every build — hover toggles this row's own `setState` on
  // every mouse enter/exit without a new `entry`, and re-running the JSON
  // decode + regex split + keyword scan below on each of those was
  // measurable overhead while scrolling/hovering a long history list.
  late int _wordCount = _computeWordCount(widget.entry);
  late List<String> _entryTags = _computeEntryTags(widget.entry);
  late IconData _avatarIcon = historyAvatarIcon(widget.entry);
  late Color _avatarCol = historyAvatarColor(widget.entry);

  static int _computeWordCount(HistoryEntry entry) {
    return computeWordCountFast(entry.content);
  }

  static List<String> _computeEntryTags(HistoryEntry entry) {
    final raw = entry.tags.trim();
    if (raw == '[]' || raw.isEmpty) return const [];
    try {
      return List<String>.from(jsonDecode(raw) as List);
    } catch (_) {
      return const [];
    }
  }

  @override
  void didUpdateWidget(HistoryEntryRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry != widget.entry) {
      _wordCount = _computeWordCount(widget.entry);
      _entryTags = _computeEntryTags(widget.entry);
      _avatarIcon = historyAvatarIcon(widget.entry);
      _avatarCol = historyAvatarColor(widget.entry);
    }
  }

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

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;

    // Row background
    final Color bg;
    if (widget.isSelected) {
      bg = isDark ? WpColorsDark.accentSubtle : WpColorsLight.accentSubtle;
    } else if (widget.isFocused || _isHovered) {
      bg = isDark ? WpColorsDark.hover : WpColorsLight.hover;
    } else {
      bg = isDark
          ? WpColorsDark.hoverTransparent
          : WpColorsLight.hoverTransparent;
    }

    final accent = isDark ? WpColorsDark.accent : WpColorsLight.accent;

    final showActions =
        (_isHovered || widget.isFocused) && !widget.multiSelectMode;

    final l10n = L10n.of(context);
    final semanticLabel = widget.entry.title.isNotEmpty
        ? widget.entry.title
        : l10n.historyUntitledRecording;

    return Semantics(
      label: semanticLabel,
      button: true,
      selected: widget.isSelected,
      // The list owns keyboard focus as a single node and tracks the
      // "current" row by index (see HistoryPage's arrow-key navigation) —
      // exposing that here lets a screen reader announce which row is
      // virtually focused instead of only showing a visual border.
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
            // Off-scale on purpose: hairline gap between tiles so adjacent
            // selection/focus borders never touch; xxs would read as a list gap.
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
              borderRadius: WpRadius.borderLg,
              // Always present (never null) so AnimatedContainer fades the
              // border's *alpha*, not its width — Border.lerp(a, null, t)
              // scales width toward zero at fixed color/alpha, which reads
              // as a flash rather than a fade for one frame (same class of
              // bug as the boxShadow fix below).
              //
              // Light-theme ink is deliberately reduced (history polish pass,
              // 2026-07-28): the light accent #06678A is itself dark
              // (rel. luminance ≈ 0.11), so the former 2 px @ 0.7 stroke was
              // the darkest ink in the whole list (≈ 3.4:1 vs the 0.92-lum
              // surface) and read as "much too dark". 1.5 px @ 0.6 keeps the
              // selection stroke at ≈ 2.9:1 (≈ 3:1, still clearly visible on
              // top of the tinted fill + lifted shadow) with ~45 % less ink.
              // Dark theme keeps the approved full-strength values.
              border: widget.isSelected
                  ? (isDark
                        ? Border.all(
                            color: accent.withValues(alpha: 0.7),
                            width: 2,
                          )
                        : Border.all(
                            color: accent.withValues(alpha: 0.6),
                            width: 1.5,
                          ))
                  : widget.isFocused
                  ? Border.all(
                      color: accent.withValues(alpha: isDark ? 0.5 : 0.45),
                      width: 1.5,
                    )
                  : Border.all(color: accent.withValues(alpha: 0), width: 1.5),
              // Weiche Ambient-Elevation nur bei Interaktion — die ruhende
              // Zeile bleibt flach (Dichte/Perf), Hover/Select/Focus bekommen
              // einen glow-freien Materiallift zusätzlich zum Border.
              // subtleTransparent (not null) for the same reason as border
              // above — see its doc comment for the exact flash mechanism.
              // Theme-resolved strength: halved black alpha on light so the
              // lift never reads as a dark halo (see WpShadows.subtleLight).
              boxShadow: (widget.isSelected || widget.isFocused || _isHovered)
                  ? WpShadows.subtleFor(isDark)
                  : WpShadows.subtleTransparent,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Multi-select checkbox
                if (widget.multiSelectMode)
                  Padding(
                    // Off-scale on purpose: top nudge centers the 24px checkbox
                    // on the tile's first text line (optical alignment).
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
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                // Avatar — colored circle with content-type icon
                HistoryEntryAvatar(
                      color: _avatarCol,
                  icon: _avatarIcon,
                  isPinned: widget.entry.pinned,
                  isDark: isDark,
                  // Off-scale on purpose: largest of the three avatar
                  // contexts — the primary list row has no competing header
                  // chrome, so the avatar carries more of the row's visual
                  // weight than the card (32) or detail header (36 default).
                  size: 42,
                ),
                const SizedBox(width: WpSpacing.sm),
                // Content
                Expanded(
                  child: _EntryRowContent(
                    entry: widget.entry,
                    isDark: isDark,
                    showActions: showActions,
                    timeLabel: _timeLabel,
                    durationLabel: _durationLabel,
                    wordCount: _wordCount,
                    tags: _entryTags,
                    onCopy: widget.onCopy,
                    onPin: widget.onPin,
                    onDelete: widget.onDelete,
                    onTagTap: widget.onTagTap,
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
// Private sub-widgets for HistoryEntryRow
// ---------------------------------------------------------------------------

class _EntryRowContent extends StatelessWidget {
  const _EntryRowContent({
    required this.entry,
    required this.isDark,
    required this.showActions,
    required this.timeLabel,
    required this.durationLabel,
    required this.wordCount,
    required this.tags,
    required this.onCopy,
    required this.onPin,
    required this.onDelete,
    this.onTagTap,
  });

  final HistoryEntry entry;
  final bool isDark;
  final bool showActions;
  final String timeLabel;
  final String durationLabel;
  final int wordCount;
  final List<String> tags;
  final VoidCallback onCopy;
  final VoidCallback onPin;
  final VoidCallback onDelete;
  final void Function(String tag)? onTagTap;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final textPrimary = isDark
        ? WpColorsDark.textPrimary
        : WpColorsLight.textPrimary;
    final textSecondary = isDark
        ? WpColorsDark.textSecondary
        : WpColorsLight.textSecondary;
    final textMuted = isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Row 1: Title + (time label OR quick actions).
        // Fixed-height slot keeps the row from jittering when
        // the trailing widget swaps between the small time
        // label and the taller action button group.
        SizedBox(
          height: 28,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: HighlightedText(
                  text: entry.title.isNotEmpty
                      ? entry.title
                      : l10n.historyUntitledRecording,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  isDark: isDark,
                  style: TextStyle(
                    // Off-scale on purpose: one step above `subheading` (14)
                    // — the preview line below stays at 14, so the title now
                    // carries real size contrast instead of only weight/color.
                    fontSize: WpTypography.heading,
                    fontWeight: FontWeight.w600,
                    color: textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: WpSpacing.xs),
              if (showActions)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // loam-ignore: a11y-interactive-semantics – semantics provided in _HistoryRowActionState.build
                    HistoryRowAction(
                      icon: LucideIcons.copy,
                      tooltip: l10n.historyCopyText,
                      isDark: isDark,
                      onTap: onCopy,
                      dense: true,
                    ),
                    // loam-ignore: a11y-interactive-semantics – semantics provided in _HistoryRowActionState.build
                    HistoryRowAction(
                      faIcon: entry.pinned ? FontAwesomeIcons.solidStar : null,
                      icon: entry.pinned ? null : LucideIcons.star,
                      activeColor: entry.pinned
                          ? WpSharedColors.pinnedAccent
                          : null,
                      tooltip: entry.pinned
                          ? l10n.historyUnpin
                          : l10n.historyPinToTop,
                      isDark: isDark,
                      onTap: onPin,
                      dense: true,
                    ),
                    // loam-ignore: a11y-interactive-semantics – semantics provided in _HistoryRowActionState.build
                    HistoryRowAction(
                      icon: LucideIcons.trash2,
                      tooltip: l10n.actionDelete,
                      isDark: isDark,
                      onTap: onDelete,
                      isDestructive: true,
                      dense: true,
                    ),
                  ],
                )
              else
                Text(
                  timeLabel,
                  style: TextStyle(
                    fontSize: WpTypography.caption,
                    color: textMuted,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 3),
        // Row 2: Content preview — two lines for more context
        HighlightedText(
          text: entry.content,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          isDark: isDark,
          style: TextStyle(
            fontSize: WpTypography.subheading,
            color: textSecondary,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 4),
        // Row 3: Subtle inline metadata (duration + language)
        _EntryMetaRow(
          durationLabel: durationLabel,
          wordCount: wordCount,
          language: entry.language,
          isLocal: entry.isLocal,
          isDark: isDark,
        ),
        // Tag chips — only rendered when entry has tags
        if (tags.isNotEmpty) ...[
          const SizedBox(height: 3),
          _EntryTagChips(tags: tags, isDark: isDark, onTagTap: onTagTap),
        ],
      ],
    );
  }
}

class _EntryMetaRow extends StatelessWidget {
  const _EntryMetaRow({
    required this.durationLabel,
    required this.wordCount,
    required this.language,
    required this.isLocal,
    required this.isDark,
  });

  final String durationLabel;
  final int wordCount;
  final String language;
  final bool isLocal;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final textMuted = isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
    final textSecondary = isDark
        ? WpColorsDark.textSecondary
        : WpColorsLight.textSecondary;
    return Row(
      children: [
        Icon(LucideIcons.clock, size: WpIconSize.xs, color: textMuted),
        const SizedBox(width: 3),
        Flexible(
          // Off-scale on purpose: only the primary metric (duration) steps up
          // from `micro`/`textMuted` to `caption`/`textSecondary` — word count
          // and language stay at micro so the row doesn't get louder overall.
          child: Text(
            durationLabel,
            style: TextStyle(
              fontSize: WpTypography.caption,
              color: textSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (wordCount > 0) ...[
          const SizedBox(width: WpSpacing.xs),
          Text(
            '· ~$wordCount w',
            style: TextStyle(fontSize: WpTypography.micro, color: textMuted),
          ),
        ],
        if (language.isNotEmpty) ...[
          const SizedBox(width: WpSpacing.xs),
          HistoryStatusChip(label: language.toUpperCase(), isDark: isDark),
        ],
        if (!isLocal) ...[
          const SizedBox(width: WpSpacing.xs),
          Text(
            '·',
            style: TextStyle(fontSize: WpTypography.micro, color: textMuted),
          ),
          const SizedBox(width: WpSpacing.xs),
          Icon(LucideIcons.cloud, size: WpIconSize.xs, color: textMuted),
        ],
      ],
    );
  }
}

class _EntryTagChips extends StatelessWidget {
  const _EntryTagChips({
    required this.tags,
    required this.isDark,
    this.onTagTap,
  });

  final List<String> tags;
  final bool isDark;
  final void Function(String tag)? onTagTap;

  @override
  Widget build(BuildContext context) {
    final accent = isDark ? WpColorsDark.accent : WpColorsLight.accent;
    final textMuted = isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
    return Wrap(
      spacing: 4,
      runSpacing: 2,
      children: [
        for (final tag in tags.take(3))
          // loam-ignore: a11y-interactive-semantics – semantics provided in _EntryTagChipState.build
          _EntryTagChip(
            tag: tag,
            isDark: isDark,
            accent: accent,
            onTap: onTagTap == null ? null : () => onTagTap!.call(tag),
          ),
        if (tags.length > 3)
          Text(
            '+${tags.length - 3}',
            style: TextStyle(fontSize: WpTypography.micro, color: textMuted),
          ),
      ],
    );
  }
}

class _EntryTagChip extends StatefulWidget {
  const _EntryTagChip({
    required this.tag,
    required this.isDark,
    required this.accent,
    required this.onTap,
  });

  final String tag;
  final bool isDark;
  final Color accent;
  final VoidCallback? onTap;

  @override
  State<_EntryTagChip> createState() => _EntryTagChipState();
}

class _EntryTagChipState extends State<_EntryTagChip> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'EntryTagChip');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      // Vertical 1 stays off-scale on purpose: the mini tag hugs its micro
      // text; xxs would double the chip height.
      padding: const EdgeInsets.symmetric(
        horizontal: WpSpacing.xxs,
        vertical: 1,
      ),
      decoration: BoxDecoration(
        color: widget.isDark
            ? WpColorsDark.accentMiniTagFill
            : WpColorsLight.accentMiniTagFill,
        borderRadius: WpRadius.borderSm,
      ),
      child: Text(
        '#${widget.tag}',
        style: TextStyle(
          fontSize: WpTypography.micro,
          color: widget.accent.withValues(alpha: 0.9),
          fontWeight: FontWeight.w500,
        ),
      ),
    );

    if (widget.onTap == null) return chip;

    return Semantics(
      button: true,
      label: '#${widget.tag}',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: WpFocusRing(
          focusNode: _focusNode,
          radius: WpRadius.sm,
          child: InkWell(
            onTap: widget.onTap,
            focusNode: _focusNode,
            borderRadius: WpRadius.borderSm,
            // WpFocusRing owns all focus visuals — suppress InkWell's own.
            focusColor: Colors.transparent,
            hoverColor: Colors.transparent,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            child: chip,
          ),
        ),
      ),
    );
  }
}
