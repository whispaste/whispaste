import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';

import 'package:whispaste/core/data/database.dart';

import '../data/providers.dart';
import 'highlighted_text.dart';
import 'history_date_header.dart';
import 'history_helpers.dart';
import '../../../widgets/wp_favourite_star.dart';
import '../../../widgets/wp_list_item_content.dart';
import '../../../widgets/wp_row_action.dart';
import '../../../widgets/wp_row_checkbox.dart';
import '../../../core/data/content_metadata_providers.dart';
import '../../../widgets/wp_copy_feedback.dart';

// ---------------------------------------------------------------------------
// Card view — responsive grid of entry cards
// ---------------------------------------------------------------------------

class HistoryCardView extends StatelessWidget {
  const HistoryCardView({
    super.key,
    this.leading,
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
    this.onRestore,
    this.isTrashView = false,
  });

  final List<DateGroup> groups;

  /// Shown above the first row, inside the same scroll owner.
  final Widget? leading;
  final String? selectedId;
  final ValueChanged<HistoryEntry> onEntryTap;
  final ValueChanged<HistoryEntry> onCopy;
  final ValueChanged<HistoryEntry> onPin;
  final ValueChanged<HistoryEntry> onDelete;
  final ValueChanged<HistoryEntry>? onDuplicate;
  final ValueChanged<HistoryEntry>? onRestore;
  final bool isTrashView;
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
          // Scroll offset survives a page switch (#1074).
          key: const PageStorageKey<String>('history-scroll-cards'),
          padding: const EdgeInsets.fromLTRB(
            sidePad,
            WpSpacing.xs,
            sidePad,
            WpSpacing.xxl,
          ),
          itemCount: flatItems.length + (leading == null ? 0 : 1),
          itemBuilder: (_, i) {
            if (leading != null) {
              if (i == 0) return leading!;
              i--;
            }
            final item = flatItems[i];
            if (item.headerLabel != null) {
              return HistoryDateHeader(
                label: resolveDateLabel(item.headerLabel!, l10n),
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
                    child: WpCopyAnchor(
                      target: 'history-${entry.id}',
                      child: HistoryEntryCard(
                        entry:
                            entry, // Same overload as the list and compact views
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
                        onDuplicate: onDuplicate != null
                            ? () => onDuplicate!(entry)
                            : null,
                        onRestore: onRestore != null
                            ? () => onRestore!(entry)
                            : null,
                        isTrashView: isTrashView,
                        multiSelectMode: multiSelectMode,
                        isChecked: selectedIds.contains(entry.id),
                      ),
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

class HistoryEntryCard extends ConsumerStatefulWidget {
  const HistoryEntryCard({
    super.key,
    this.onRestore,
    this.isTrashView = false,
    required this.entry,
    required this.isSelected,
    required this.onTap,
    required this.onCopy,
    required this.onPin,
    required this.onDelete,
    this.onDuplicate,
    required this.multiSelectMode,
    required this.isChecked,
    this.isFocused = false,
  });

  final HistoryEntry entry;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onCopy;
  final VoidCallback onPin;
  final VoidCallback onDelete;
  final VoidCallback? onDuplicate;
  final VoidCallback? onRestore;
  final bool isTrashView;
  final bool multiSelectMode;
  final bool isChecked;
  final bool isFocused;

  @override
  ConsumerState<HistoryEntryCard> createState() => _HistoryEntryCardState();
}

class _HistoryEntryCardState extends ConsumerState<HistoryEntryCard> {
  bool _isHovered = false;

  /// Fixed card height — sized to fit the title row, a 3-line preview,
  /// and the metadata row without per-entry content changing the grid's
  /// row height (see `cardWidth` above for the analogous width rule).
  static const double _cardHeight = 180;

  /// Palette for the card chrome — pulled out of [build] so its branching
  /// doesn't count against that method's own complexity.
  ///
  /// Every state cue here is a *fill or an edge*, never a lift: see the
  /// `boxShadow` note in [build] and *The Depth-Source Rule*.
  ({
    Color accent,
    Color textPrimary,
    Color textSecondary,
    Color textMuted,
    Color fill,
    Color borderColor,
  })
  _resolveColors() {
    final accent = WpColors.accent;
    final isActive = widget.isSelected || widget.isFocused || _isHovered;
    final borderColor = widget.isSelected
        ? accent.withValues(alpha: 0.5)
        : widget.isFocused
        ? accent.withValues(alpha: 0.4)
        // Hover takes the tinted rim `WpListTileSurface`'s card variant uses
        // for the same state on the list rows this grid is an alternative
        // view of — a white rim over a chromatic frost fill is the "reads
        // grey" failure the material exists to avoid.
        : _isHovered
        ? WpColors.cardEdgeHighlight
        : WpColors.borderSubtle;
    // The card material, same as `WpListTileSurface`'s card variant paints
    // for those rows: a translucent frost plate over the one ambient
    // gradient, not an opaque tile. Hover/focus/selection lift it by one
    // rung rather than by a shadow — the brightness delta *is* the depth.
    final restingSurface = isActive
        ? WpColors.cardFillElevated
        : WpColors.cardFill;
    return (
      accent: accent,
      textPrimary: WpColors.textPrimary,
      textSecondary: WpColors.textSecondary,
      textMuted: WpColors.textMuted,
      // Selected cards get the same accent wash the list tile paints
      // (history_list_tile.dart:114) — composited over the card's own
      // frost fill rather than replacing it, so the grid keeps its
      // material. Without a fill the only selection cue was a 0.5-alpha
      // hairline border, which is far too quiet to scan a 4-column grid
      // for "what did Ctrl+A just check?".
      fill: widget.isSelected
          ? Color.alphaBlend(WpColors.accentSubtle, restingSurface)
          : restingSurface,
      borderColor: borderColor,
    );
  }

  @override
  Widget build(BuildContext context) {
    final wordCount =
        ref
            .watch(
              contentMetadataProvider((
                kind: ContentKind.recording,
                id: widget.entry.id,
              )),
            )
            .value
            ?.wordCount ??
        0;
    final l10n = L10n.of(context);
    final colors = _resolveColors();
    final textPrimary = colors.textPrimary;
    final textSecondary = colors.textSecondary;
    final textMuted = colors.textMuted;
    final fill = colors.fill;
    final borderColor = colors.borderColor;

    // Suppressed in multi-select like the other two views.
    final showActions =
        (_isHovered || widget.isFocused) && !widget.multiSelectMode;

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
              color: fill,
              borderRadius: WpRadius.borderLg,
              border: Border.all(color: borderColor),
              // No lift, in any state (Ticket 13, *The Depth-Source Rule*).
              // This tile used to carry `WpShadows.subtle` at rest and
              // `WpShadows.card` while active; the argument for it was a
              // light-theme one — halve the black alpha on pearl so the lift
              // isn't a dark outline — and the light theme was removed on
              // 2026-08-11. What was left is the case the rule exists to
              // keep out: a black shadow on a near-black ground, muddying
              // the one ambient gradient the frost fill is there to let
              // through. Both twins named beside it in DESIGN.md have since
              // dropped theirs (`wp_list_tile_surface.dart`, Ticket 08; the
              // former entry avatar), and hover/focus/
              // selection now read through the fill rung and the edge in
              // [_resolveColors] instead. Gated by
              // `test/core/design/depth_source_test.dart`.
              boxShadow: null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row: type glyph + title + hover actions. Held at the
                // dense action box height, so revealing the actions never
                // shifts the preview below.
                ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: WpListItemContent.titleLineHeight,
                  ),
                  child: Row(
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
                          ),
                        ),
                      // The list row's type glyph (#1498): no coloured disc.
                      const WpListItemTypeGlyph(icon: historyAvatarIcon),
                      const SizedBox(width: WpSpacing.sm),
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
                            style: TextStyle(
                              fontSize: WpTypography.subheading,
                              fontWeight: FontWeight.w700,
                              color: textPrimary,
                            ),
                          ),
                        ),
                      ),
                      // A favourite keeps its star visible at rest, as in the
                      // list row: the star is the only carrier of that state.
                      if (widget.entry.pinned && !showActions) ...[
                        const SizedBox(width: WpSpacing.xs),
                        WpListItemStarMark(
                          key: ValueKey(
                            'history-card-favourite-mark-${widget.entry.id}',
                          ),
                          semanticsLabel: l10n.listItemFavouriteMark,
                        ),
                      ],
                      // Action buttons — revealed on hover/focus. Dense, so they
                      // fit the title row's fixed height.
                      WpRowActions(
                        // Suppressed in multi-select like the other two views:
                        // a per-card Delete next to a live batch selection is
                        // an easy misfire.
                        visible: showActions,
                        dense: true,
                        children: [
                          if (widget.isTrashView &&
                              widget.onRestore != null) ...[
                            WpRowAction(
                              icon: LucideIcons.undo2,
                              tooltip: l10n.historyRestore,
                              onTap: widget.onRestore!,
                              dense: true,
                            ),
                            WpRowAction(
                              icon: LucideIcons.trash2,
                              tooltip: l10n.historyDeleteForever,
                              onTap: widget.onDelete,
                              isDestructive: true,
                              dense: true,
                            ),
                          ] else ...[
                            WpRowAction(
                              icon: LucideIcons.copy,
                              tooltip: l10n.historyCopyText,
                              onTap: widget.onCopy,
                              dense: true,
                            ),
                            WpFavouriteStar(
                              isFavourite: widget.entry.pinned,
                              onToggle: widget.onPin,
                            ),
                            if (widget.onDuplicate case final onDuplicate?)
                              WpRowAction(
                                icon: LucideIcons.files,
                                tooltip: l10n.actionDuplicate,
                                onTap: onDuplicate,
                                dense: true,
                              ),
                            WpRowAction(
                              icon: LucideIcons.trash2,
                              tooltip: l10n.actionDelete,
                              onTap: widget.onDelete,
                              isDestructive: true,
                              dense: true,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: WpSpacing.xs),
                // Content preview (3-4 lines)
                Expanded(
                  child: HighlightedText(
                    text: widget.entry.content,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
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
                    const SizedBox(width: WpSpacing.xxs),
                    Text(
                      formatHistoryDuration(widget.entry.durationSec),
                      style: TextStyle(
                        fontSize: WpTypography.caption,
                        color: textMuted,
                      ),
                    ),
                    if (wordCount > 0) ...[
                      const SizedBox(width: WpSpacing.xs),
                      Text(
                        '· ~$wordCount w',
                        style: TextStyle(
                          fontSize: WpTypography.caption,
                          color: textMuted,
                        ),
                      ),
                    ],
                    if (widget.entry.language.isNotEmpty) ...[
                      const SizedBox(width: WpSpacing.xs),
                      HistoryStatusChip(
                        label: widget.entry.language.toUpperCase(),
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
