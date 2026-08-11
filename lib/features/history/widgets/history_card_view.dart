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
import '../../../widgets/wp_row_action.dart';
import '../../../widgets/wp_row_checkbox.dart';
import '../../../core/utils/word_count.dart';

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
        // Page inset, owned by the list below so that cards *and* date
        // headers start on the filter bar's `xl` vertical — the card view was
        // the third of history's three modes sitting inside it (ticket 03,
        // point 5). Also the divisor for the column maths, hence the const.
        const sidePad = WpSpacing.xl;
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
          padding: const EdgeInsets.fromLTRB(
            sidePad,
            WpSpacing.xs,
            sidePad,
            WpSpacing.xxl,
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
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final entry in item.entries!)
                  SizedBox(
                    key: ValueKey(entry.id),
                    width: cardWidth,
                    // loam-ignore: a11y-interactive-semantics – semantics provided in _HistoryEntryCardState.build
                    child: HistoryEntryCard(
                      entry: entry,
                      isDark: isDark,
                      // Same overload as the list and compact views
                      // (history_list_view.dart:69): outside multi-select
                      // `isSelected` means "open in the detail panel", inside
                      // it means "checked". The card used to ignore the
                      // multi-select state entirely, so Ctrl+A filled the
                      // action bar with "n selected" while every card kept
                      // its resting look and the following Delete hit a set
                      // the user could not see.
                      isSelected: multiSelectMode
                          ? selectedIds.contains(entry.id)
                          : entry.id == selectedId,
                      // The arrow cursor is suppressed in multi-select for
                      // the same reason as in the other two views: there the
                      // checkbox column, not the cursor ring, is the state
                      // the user is manipulating.
                      isFocused: !multiSelectMode && entry.id == focusedId,
                      onTap: () => onEntryTap(entry),
                      onCopy: () => onCopy(entry),
                      onPin: () => onPin(entry),
                      onDelete: () => onDelete(entry),
                      multiSelectMode: multiSelectMode,
                      isChecked: selectedIds.contains(entry.id),
                    ),
                  ),
              ],
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
    required this.isChecked,
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
  final bool isChecked;
  final bool isFocused;

  @override
  State<HistoryEntryCard> createState() => _HistoryEntryCardState();
}

class _HistoryEntryCardState extends State<HistoryEntryCard> {
  bool _isHovered = false;

  /// Fixed card height — sized to fit avatar/title row, a 3-line preview,
  /// and the metadata row without per-entry content changing the grid's
  /// row height (see `cardWidth` above for the analogous width rule).
  static const double _cardHeight = 180;

  // Memoized once per `entry` change, not recomputed on every hover
  // setState — see the identical fix in history_list_tile.dart for why.
  late int _wordCount = _computeWordCount(widget.entry);
  late IconData _avatarIcon = historyAvatarIcon(widget.entry);
  // The *slot*, not its color — see the identical note in history_list_tile.dart.
  late WpCategorySlot _avatarSlot = historyAvatarSlot(widget.entry);

  static int _computeWordCount(HistoryEntry entry) {
    return computeWordCountFast(entry.content);
  }

  @override
  void didUpdateWidget(HistoryEntryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry != widget.entry) {
      _wordCount = _computeWordCount(widget.entry);
      _avatarIcon = historyAvatarIcon(widget.entry);
      _avatarSlot = historyAvatarSlot(widget.entry);
    }
  }

  /// Theme-resolved palette for the card chrome — pulled out of [build] so
  /// its branching doesn't count against that method's own complexity.
  ///
  /// Light-theme accent strokes are slightly reduced (history polish pass):
  /// the light accent #06678A is itself dark, so equal alphas read heavier
  /// on the pearl surfaces than on dark navy. Mirrors the list tile.
  ({
    Color accent,
    Color textPrimary,
    Color textSecondary,
    Color textMuted,
    Color surfaceElevated,
    Color borderColor,
  })
  _resolveColors(bool isDark) {
    final accent = isDark ? WpColorsDark.accent : WpColorsLight.accent;
    final borderColor = widget.isSelected
        ? accent.withValues(alpha: isDark ? 0.5 : 0.45)
        : widget.isFocused
        ? accent.withValues(alpha: isDark ? 0.4 : 0.35)
        : (isDark ? WpColorsDark.borderSubtle : WpColorsLight.borderSubtle);
    final restingSurface = isDark
        ? WpColorsDark.surfaceElevated
        : WpColorsLight.surfaceElevated;
    return (
      accent: accent,
      textPrimary: isDark
          ? WpColorsDark.textPrimary
          : WpColorsLight.textPrimary,
      textSecondary: isDark
          ? WpColorsDark.textSecondary
          : WpColorsLight.textSecondary,
      textMuted: isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted,
      // Selected cards get the same accent wash the list tile paints
      // (history_list_tile.dart:114) — composited over the card's own
      // elevated fill rather than replacing it, so the grid keeps its
      // material. Without a fill the only selection cue was a 0.5-alpha
      // hairline border, which is far too quiet to scan a 4-column grid
      // for "what did Ctrl+A just check?".
      surfaceElevated: widget.isSelected
          ? Color.alphaBlend(
              isDark ? WpColorsDark.accentSubtle : WpColorsLight.accentSubtle,
              restingSurface,
            )
          : restingSurface,
      borderColor: borderColor,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final l10n = L10n.of(context);
    final colors = _resolveColors(isDark);
    final textPrimary = colors.textPrimary;
    final textSecondary = colors.textSecondary;
    final textMuted = colors.textMuted;
    final surfaceElevated = colors.surfaceElevated;
    final borderColor = colors.borderColor;

    final semanticLabel = widget.entry.title.isNotEmpty
        ? widget.entry.title
        : l10n.historyUntitledRecording;

    return Semantics(
      // Group variant of the house idiom — see history_list_tile.dart:134 for
      // the full reasoning; the card holds the same several interactive nodes,
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
            height: _cardHeight,
            padding: const EdgeInsets.all(WpSpacing.md),
            decoration: BoxDecoration(
              color: surfaceElevated,
              borderRadius: WpRadius.borderLg,
              border: Border.all(color: borderColor),
              // Weiche Ambient-Elevation: die Kachel trägt immer einen
              // dezenten Materiallift (subtle), Hover/Select/Focus vertiefen
              // ihn (card) — glow-frei, siehe WpShadows. Theme-resolved:
              // im Light-Theme mit halbierter Schwarz-Alpha, damit der Lift
              // auf den Pearl-Flächen kein dunkler Halo wird (die volle
              // card-Stärke lag bei ≈ 1.6:1 gegen die Surface — deutlich
              // sichtbare Dunkelzone um jede gehoverte Kachel).
              boxShadow: (widget.isSelected || widget.isFocused || _isHovered)
                  ? WpShadows.cardFor(isDark)
                  : WpShadows.subtleFor(isDark),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row: avatar + title + hover actions
                Row(
                  children: [
                    // Multi-select checkbox — same leading position and same
                    // control as the list and compact rows, so the checked
                    // state is visible and operable in every view mode.
                    if (widget.multiSelectMode)
                      Padding(
                        padding: const EdgeInsets.only(right: WpSpacing.xs),
                        child: WpRowCheckbox(
                          value: widget.isChecked,
                          onChanged: widget.onTap,
                          isDark: isDark,
                        ),
                      ),
                    HistoryEntryAvatar(
                      color: _avatarSlot.color(isDark),
                      icon: _avatarIcon,
                      isPinned: widget.entry.pinned,
                      isDark: isDark,
                      // Off-scale on purpose: smallest of the three avatar
                      // contexts — the card's title row is tight and shares
                      // space with hover actions (see history_list_tile.dart's
                      // 42 for the roomier list row, history_detail_panel.dart's
                      // 36 default for the header).
                      size: 32,
                    ),
                    const SizedBox(width: WpSpacing.xs),
                    Expanded(
                      // Duplicate of the wrapper's label — excluded so the
                      // card's title is announced once, not twice. The preview
                      // and metadata below stay announced.
                      child: ExcludeSemantics(
                        child: HighlightedText(
                          text: widget.entry.title.isNotEmpty
                              ? widget.entry.title
                              : l10n.historyUntitledRecording,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          isDark: isDark,
                          style: TextStyle(
                            fontSize: WpTypography.subheading,
                            fontWeight: FontWeight.w700,
                            color: textPrimary,
                          ),
                        ),
                      ),
                    ),
                    // Action buttons — revealed on hover/focus. Dense, so the
                    // 32px avatar keeps setting the title row's height and
                    // the preview below never shifts when they appear.
                    WpRowActions(
                      // Suppressed in multi-select like the other two views:
                      // a per-card Delete next to a live batch selection is
                      // an easy misfire.
                      visible:
                          (_isHovered || widget.isFocused) &&
                          !widget.multiSelectMode,
                      dense: true,
                      children: [
                        // loam-ignore: a11y-interactive-semantics – semantics provided in _WpRowActionState.build
                        WpRowAction(
                          icon: LucideIcons.copy,
                          tooltip: l10n.historyCopyText,
                          isDark: isDark,
                          onTap: widget.onCopy,
                          dense: true,
                        ),
                        // loam-ignore: a11y-interactive-semantics – semantics provided in _WpRowActionState.build
                        WpRowAction(
                          faIcon: widget.entry.pinned
                              ? FontAwesomeIcons.solidStar
                              : null,
                          icon: widget.entry.pinned ? null : LucideIcons.star,
                          activeColor: widget.entry.pinned
                              ? WpSharedColors.pinnedAccent
                              : null,
                          tooltip: widget.entry.pinned
                              ? l10n.historyUnpin
                              : l10n.historyPinToTop,
                          isDark: isDark,
                          onTap: widget.onPin,
                          dense: true,
                        ),
                        // loam-ignore: a11y-interactive-semantics – semantics provided in _WpRowActionState.build
                        WpRowAction(
                          icon: LucideIcons.trash2,
                          tooltip: l10n.actionDelete,
                          isDark: isDark,
                          onTap: widget.onDelete,
                          isDestructive: true,
                          dense: true,
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
                      fontSize: WpTypography.body,
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
                      style: TextStyle(
                        fontSize: WpTypography.micro,
                        color: textMuted,
                      ),
                    ),
                    if (_wordCount > 0) ...[
                      const SizedBox(width: WpSpacing.xs),
                      Text(
                        '· ~$_wordCount w',
                        style: TextStyle(
                          fontSize: WpTypography.micro,
                          color: textMuted,
                        ),
                      ),
                    ],
                    if (widget.entry.language.isNotEmpty) ...[
                      const SizedBox(width: WpSpacing.xs),
                      HistoryStatusChip(
                        label: widget.entry.language.toUpperCase(),
                        isDark: isDark,
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
