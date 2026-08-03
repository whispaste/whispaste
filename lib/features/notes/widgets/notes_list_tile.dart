import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/data/database.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../data/note_title.dart';

// ---------------------------------------------------------------------------
// Note list tile — simplified sibling of HistoryEntryRow: derived title,
// content preview, relative date, plus per-note actions (favourite star in
// the active view, restore/delete-forever in the trash view).
// ---------------------------------------------------------------------------

class NotesListTile extends StatefulWidget {
  const NotesListTile({
    super.key,
    required this.note,
    required this.isDark,
    required this.isTrashView,
    required this.isSelected,
    required this.onTap,
    required this.onFavoriteToggle,
    required this.onRestore,
    required this.onDeleteForever,
  });

  final Note note;
  final bool isDark;

  /// Trash view swaps the leading favourite star for trailing
  /// restore/delete-forever actions.
  final bool isTrashView;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onFavoriteToggle;
  final VoidCallback onRestore;
  final VoidCallback onDeleteForever;

  @override
  State<NotesListTile> createState() => _NotesListTileState();
}

class _NotesListTileState extends State<NotesListTile> {
  bool _isHovered = false;

  // Memoized once per `note` change (initState + didUpdateWidget) — hover
  // toggles this tile's own setState on every mouse enter/exit, and
  // re-deriving title/preview from a potentially long content string on each
  // of those would be wasted work (same pattern as _HistoryEntryRowState).
  late String? _title = deriveNoteTitle(widget.note.content);
  late String _preview = _derivePreview(widget.note.content);

  /// Cap for how much content the preview derivation scans — the preview
  /// shows at most two ellipsized lines, so scanning a multi-kilobyte note
  /// in full would be pure overhead.
  static const _previewScanLimit = 500;

  /// Everything after the first non-blank (title) line, blank lines dropped,
  /// joined into a single run for the two-line ellipsized preview.
  static String _derivePreview(String content) {
    final scanned = content.length > _previewScanLimit
        ? content.substring(0, _previewScanLimit)
        : content;
    var titleSeen = false;
    final rest = <String>[];
    for (final line in scanned.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (!titleSeen) {
        titleSeen = true;
        continue;
      }
      rest.add(trimmed);
    }
    return rest.join(' ');
  }

  @override
  void didUpdateWidget(NotesListTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.note != widget.note) {
      _title = deriveNoteTitle(widget.note.content);
      _preview = _derivePreview(widget.note.content);
    }
  }

  /// Relative label for [Note.updatedAt]: today → HH:MM, yesterday →
  /// localized "Yesterday", else a short localized date (year only when it
  /// differs). Minimal local analogue of the history tile's time labeling —
  /// history has no exported relative-date helper to reuse.
  String _relativeDateLabel(BuildContext context) {
    final t = widget.note.updatedAt;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(t.year, t.month, t.day);
    if (day == today) {
      return '${t.hour.toString().padLeft(2, '0')}:'
          '${t.minute.toString().padLeft(2, '0')}';
    }
    if (day == today.subtract(const Duration(days: 1))) {
      return L10n.of(context).historyYesterday;
    }
    final locale = Localizations.localeOf(context).toString();
    return t.year == now.year
        ? DateFormat.MMMd(locale).format(t)
        : DateFormat.yMMMd(locale).format(t);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final l10n = L10n.of(context);

    // Tile background — mirrors HistoryEntryRow's hover/selection states.
    final Color bg;
    if (widget.isSelected) {
      bg = isDark ? WpColorsDark.accentSubtle : WpColorsLight.accentSubtle;
    } else if (_isHovered) {
      bg = isDark ? WpColorsDark.hover : WpColorsLight.hover;
    } else {
      bg = isDark
          ? WpColorsDark.hoverTransparent
          : WpColorsLight.hoverTransparent;
    }

    final accent = isDark ? WpColorsDark.accent : WpColorsLight.accent;
    final textPrimary = isDark
        ? WpColorsDark.textPrimary
        : WpColorsLight.textPrimary;
    final textSecondary = isDark
        ? WpColorsDark.textSecondary
        : WpColorsLight.textSecondary;
    final textMuted = isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;

    final title = _title ?? l10n.notesUntitled;

    return Semantics(
      label: title,
      button: true,
      selected: widget.isSelected,
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
            // selection borders never touch (same as HistoryEntryRow).
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
              // Always-present border/shadow (alpha-faded, never null) — see
              // HistoryEntryRow's doc comments for the lerp-flash mechanism
              // and the reduced light-theme selection ink.
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
                  : Border.all(color: accent.withValues(alpha: 0), width: 1.5),
              boxShadow: (widget.isSelected || _isHovered)
                  ? WpShadows.subtleFor(isDark)
                  : WpShadows.subtleTransparent,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Row 1: favourite toggle + title + relative date (+ trash
                // actions when the trash filter is active)
                Row(
                  children: [
                    if (!widget.isTrashView) ...[
                      _TileAction(
                        tooltip: widget.note.pinned
                            ? l10n.notesUnfavorite
                            : l10n.notesFavorite,
                        onTap: widget.onFavoriteToggle,
                        // Solid amber star when pinned, muted outline star
                        // otherwise — always visible so the tap target
                        // doesn't appear/disappear with the pin state.
                        child: FaIcon(
                          widget.note.pinned
                              ? FontAwesomeIcons.solidStar
                              : FontAwesomeIcons.star,
                          size: 12,
                          color: widget.note.pinned
                              ? WpSharedColors.pinnedAccent
                              : textMuted,
                        ),
                      ),
                      const SizedBox(width: WpSpacing.xxs),
                    ],
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: WpTypography.heading,
                          fontWeight: FontWeight.w600,
                          color: textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: WpSpacing.xs),
                    Text(
                      _relativeDateLabel(context),
                      style: TextStyle(
                        fontSize: WpTypography.caption,
                        color: textMuted,
                      ),
                    ),
                    if (widget.isTrashView) ...[
                      const SizedBox(width: WpSpacing.xs),
                      _TileAction(
                        tooltip: l10n.notesRestore,
                        onTap: widget.onRestore,
                        child: Icon(
                          // Same restore glyph as the editor toolbar and
                          // history's per-item restore action.
                          LucideIcons.undo2,
                          size: WpIconSize.xs,
                          color: textMuted,
                        ),
                      ),
                      const SizedBox(width: WpSpacing.xxs),
                      _TileAction(
                        tooltip: l10n.notesDeleteForever,
                        onTap: widget.onDeleteForever,
                        child: Icon(
                          LucideIcons.trash2,
                          size: WpIconSize.xs,
                          color: isDark
                              ? WpColorsDark.error
                              : WpColorsLight.error,
                        ),
                      ),
                    ],
                  ],
                ),
                // Row 2: content preview — hidden when the note is title-only
                if (_preview.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    _preview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: WpTypography.subheading,
                      color: textSecondary,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Compact per-tile icon action — deliberately NOT an IconButton: Material's
// 40x40 minimum would inflate the tile row. The inner GestureDetector wins
// hit-testing over the tile's own tap handler, so tapping an action never
// also selects the note.
// ---------------------------------------------------------------------------

class _TileAction extends StatefulWidget {
  const _TileAction({
    required this.tooltip,
    required this.onTap,
    required this.child,
  });

  final String tooltip;
  final VoidCallback onTap;
  final Widget child;

  @override
  State<_TileAction> createState() => _TileActionState();
}

class _TileActionState extends State<_TileAction> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.tooltip,
      button: true,
      // Global tooltip waitDuration comes from the app theme (theme.dart).
      child: Tooltip(
        message: widget.tooltip,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: GestureDetector(
            onTap: widget.onTap,
            child: AnimatedOpacity(
              duration: WpMotion.durationFor(
                context,
                _isHovered ? WpMotion.hoverIn : WpMotion.hoverOut,
              ),
              opacity: _isHovered ? 1.0 : 0.75,
              // Off-scale padding on purpose: pads the ~12px glyph to a
              // ~20px hit area without stretching the tile row.
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
