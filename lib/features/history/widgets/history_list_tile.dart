import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/wp_focus_ring.dart';
import '../../../widgets/wp_list_tile_surface.dart';
import '../../../widgets/wp_row_action.dart';
import '../../../widgets/wp_row_checkbox.dart';
import 'package:whispaste/core/data/database.dart';
import 'highlighted_text.dart';
import 'history_helpers.dart';
import '../../../core/utils/word_count.dart';

// ---------------------------------------------------------------------------
// History entry row — WhatsApp/ChatGPT/Discord-inspired
// ---------------------------------------------------------------------------

class HistoryEntryRow extends StatefulWidget {
  const HistoryEntryRow({
    super.key,
    required this.entry,
    required this.isSelected,
    required this.onTap,
    required this.onCopy,
    required this.onPin,
    required this.onDelete,
    this.onRestore,
    this.onDuplicate,
    this.multiSelectMode = false,
    this.isChecked = false,
    this.isTrashView = false,
    this.isFocused = false,
    this.inSplitView = false,
    this.onTagTap,
  });

  final HistoryEntry entry;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onCopy;
  final VoidCallback onPin;
  final VoidCallback onDelete;
  final VoidCallback? onRestore;
  final VoidCallback? onDuplicate;
  final bool multiSelectMode;
  final bool isChecked;
  final bool isTrashView;
  final bool isFocused;

  /// Whether a detail pane is open beside the list. Split rows are transparent
  /// panel rows with a two-line preview; overview rows (no detail) are quiet
  /// cards with a one-line preview that uses the full row width.
  final bool inSplitView;
  final void Function(String tag)? onTagTap;

  @override
  State<HistoryEntryRow> createState() => _HistoryEntryRowState();
}

class _HistoryEntryRowState extends State<HistoryEntryRow> {
  bool _isHovered = false;

  // Memoized once per `entry` change (initState + didUpdateWidget), not
  // recomputed on every build — hover toggles this row's own `setState` on
  // every mouse enter/exit without a new `entry`, and re-running the JSON
  // decode + regex split below on each of those was measurable overhead
  // while scrolling/hovering a long history list.
  late int _wordCount = _computeWordCount(widget.entry);
  late List<String> _entryTags = _computeEntryTags(widget.entry);
  // Held for a different reason than the two above — a list index costs
  // nothing to repeat. What this field buys is the *slot* rather than its
  // color: the cache outlives a runtime theme switch, which only `entry`
  // invalidates, so a resolved color would keep painting the old theme's hue
  // until the row happened to get a new entry.
  late WpCategorySlot _avatarSlot = historyAvatarSlot(widget.entry);

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
      _avatarSlot = historyAvatarSlot(widget.entry);
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

  /// Right-click menu: the same actions as the hover buttons, so a row can
  /// be handled without hovering its trailing icons (UIA-HIS-32).
  Future<void> _showContextMenu(Offset globalPosition) async {
    final l10n = L10n.of(context);
    final entry = widget.entry;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final choice = await showMenu<VoidCallback>(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & Size.zero,
        Offset.zero & overlay.size,
      ),
      items: [
        if (widget.isTrashView) ...[
          if (widget.onRestore case final onRestore?)
            PopupMenuItem(value: onRestore, child: Text(l10n.historyRestore)),
          PopupMenuItem(
            value: widget.onDelete,
            child: Text(l10n.historyDeleteForever),
          ),
        ] else ...[
          PopupMenuItem(
            value: widget.onCopy,
            child: Text(l10n.historyCopyText),
          ),
          PopupMenuItem(
            value: widget.onPin,
            child: Text(
              entry.pinned ? l10n.historyUnpin : l10n.historyPinToTop,
            ),
          ),
          if (widget.onDuplicate case final onDuplicate?)
            PopupMenuItem(
              value: onDuplicate,
              child: Text(l10n.actionDuplicate),
            ),
          PopupMenuItem(value: widget.onDelete, child: Text(l10n.actionDelete)),
        ],
      ],
    );
    choice?.call();
  }

  @override
  Widget build(BuildContext context) {
    final showActions =
        (_isHovered || widget.isFocused) && !widget.multiSelectMode;

    final l10n = L10n.of(context);
    final semanticLabel = widget.entry.title.isNotEmpty
        ? widget.entry.title
        : l10n.historyUntitledRecording;

    return Semantics(
      // House idiom, group variant (`no_double_announcement_test.dart`): the
      // wrapper keeps its `label:` and the rendered title is hidden with
      // ExcludeSemantics below, because this subtree holds several interactive
      // nodes (checkbox, three row actions, tag chips). MergeSemantics — the
      // other permitted shape — would swallow all of them into one node.
      label: semanticLabel,
      button: true,
      // `selected:` follows the arrow cursor, not the detail-panel selection.
      // The list holds a single Focus node and the arrow keys move nothing but
      // an optical highlight, so without this flag a screen reader reported no
      // change at all while the user arrowed through the list — the same defect
      // already fixed in the snippet picker, the export picker and the tag
      // input, all of which map `selected:` onto the highlight.
      //
      // Exactly one row may report selected at a time in single-select mode,
      // which is why this is not `isSelected || isFocused`: after a click both
      // coincide anyway, and while arrowing away from a clicked row the cursor
      // — the row Enter and Delete will act on — is the one worth announcing.
      // Inside multi-select the cursor is suppressed (history_list_view.dart:72)
      // and `isSelected` carries the checked state, so the flag reports the
      // checked rows instead, which is correct for a multi-selection.
      selected: widget.multiSelectMode ? widget.isSelected : widget.isFocused,
      focused: widget.isFocused,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          onSecondaryTapUp: widget.multiSelectMode
              ? null
              : (details) => _showContextMenu(details.globalPosition),
          child: WpListTileSurface(
            variant: widget.inSplitView
                ? WpListTileVariant.panel
                : WpListTileVariant.overview,
            isHovered: _isHovered,
            isFocused: widget.isFocused,
            isSelected: widget.isSelected,
            // Actions stay inside the content: the three of them share the
            // metadata line with the timestamp, not the envelope.
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
                    child: WpRowCheckbox(
                      value: widget.isChecked,
                      onChanged: widget.onTap,
                    ),
                  ),
                // Avatar — colored circle, one shared glyph: the app
                // classifies nothing, so the icon says only "dictation
                // transcript" and the hue is decoration.
                HistoryEntryAvatar(
                  color: _avatarSlot.color(),
                  icon: historyAvatarIcon,
                  isPinned: widget
                      .entry
                      .pinned, // Off-scale on purpose: largest of the three avatar
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
                    inSplitView: widget.inSplitView,
                    showActions: showActions,
                    timeLabel: _timeLabel,
                    durationLabel: _durationLabel,
                    wordCount: _wordCount,
                    tags: _entryTags,
                    onCopy: widget.onCopy,
                    onPin: widget.onPin,
                    onDelete: widget.onDelete,
                    onRestore: widget.onRestore,
                    isTrashView: widget.isTrashView,
                    onDuplicate: widget.onDuplicate,
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
    required this.inSplitView,
    required this.showActions,
    required this.timeLabel,
    required this.durationLabel,
    required this.wordCount,
    required this.tags,
    required this.onCopy,
    required this.onPin,
    required this.onDelete,
    this.onRestore,
    this.isTrashView = false,
    this.onDuplicate,
    this.onTagTap,
  });

  final HistoryEntry entry;
  final bool inSplitView;
  final bool showActions;
  final String timeLabel;
  final String durationLabel;
  final int wordCount;
  final List<String> tags;
  final VoidCallback onCopy;
  final VoidCallback onPin;
  final VoidCallback onDelete;
  final VoidCallback? onRestore;
  final bool isTrashView;
  final VoidCallback? onDuplicate;
  final void Function(String tag)? onTagTap;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final textPrimary = WpColors.textPrimary;
    final textSecondary = WpColors.textSecondary;
    // In the trash only restore and permanent delete make sense (UIA-HIS-09).
    final restore = onRestore;
    final actions = WpRowActions(
      visible: showActions,
      dense: true,
      children: [
        if (isTrashView && restore != null) ...[
          // loam-ignore: a11y-interactive-semantics – semantics provided in _WpRowActionState.build
          WpRowAction(
            icon: LucideIcons.undo2,
            tooltip: l10n.historyRestore,
            onTap: restore,
            dense: true,
          ),
          // loam-ignore: a11y-interactive-semantics – semantics provided in _WpRowActionState.build
          WpRowAction(
            icon: LucideIcons.trash2,
            tooltip: l10n.historyDeleteForever,
            onTap: onDelete,
            isDestructive: true,
            dense: true,
          ),
        ] else ...[
          // loam-ignore: a11y-interactive-semantics – semantics provided in _WpRowActionState.build
          WpRowAction(
            icon: LucideIcons.copy,
            tooltip: l10n.historyCopyText,
            onTap: onCopy,
            dense: true,
          ),
          // loam-ignore: a11y-interactive-semantics – semantics provided in _WpRowActionState.build
          WpRowAction(
            faIcon: entry.pinned ? FontAwesomeIcons.solidStar : null,
            icon: entry.pinned ? null : LucideIcons.star,
            activeColor: entry.pinned ? WpSharedColors.pinnedAccent : null,
            tooltip: entry.pinned ? l10n.historyUnpin : l10n.historyPinToTop,
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
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Row 1: the title, with the row actions at its end. The actions take
        // width only while the row is active (selected, hovered or focused),
        // and then the title gives way. The metadata line below keeps the full
        // row width: time and duration are what tell recordings apart when the
        // title is long, so they must never be squeezed into a stub.
        Row(
          children: [
            Expanded(
              child: ExcludeSemantics(
                // Excluded because the row's Semantics wrapper already carries
                // this exact string as its label; without this the title was
                // announced twice. The preview and metadata stay announced —
                // they are content.
                child: HighlightedText(
                  text: entry.title.isNotEmpty
                      ? entry.title
                      : l10n.historyUntitledRecording,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: WpTypography.subheading,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                    color: textPrimary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: WpSpacing.xs),
            actions,
          ],
        ),
        const SizedBox(height: 3),
        // Row 2: content preview. Two lines in a split panel, one in the
        // overview, where the row is wide enough to show more on one line.
        HighlightedText(
          text: entry.content,
          maxLines: inSplitView ? 2 : 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: WpTypography.body,
            color: textSecondary,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 4),
        // Row 3: metadata, full width.
        _EntryMetaRow(
          timeLabel: timeLabel,
          durationLabel: durationLabel,
          wordCount: wordCount,
          language: entry.language,
          isLocal: entry.isLocal,
        ),
        // Tag chips — only rendered when entry has tags
        if (tags.isNotEmpty) ...[
          const SizedBox(height: 3),
          _EntryTagChips(tags: tags, onTagTap: onTagTap),
        ],
      ],
    );
  }
}

class _EntryMetaRow extends StatelessWidget {
  const _EntryMetaRow({
    required this.timeLabel,
    required this.durationLabel,
    required this.wordCount,
    required this.language,
    required this.isLocal,
  });

  final String timeLabel;
  final String durationLabel;
  final int wordCount;
  final String language;
  final bool isLocal;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final textMuted = WpColors.textMuted;
    final textSecondary = WpColors.textSecondary;
    final metaStyle = TextStyle(
      fontSize: WpTypography.caption,
      color: textMuted,
    );
    // One text run, so the line ellipsizes as a whole and can never overflow
    // the space beside the row actions. Icons and the status chip sit inline
    // as widget spans. Every fact is joined by the same separator.
    final separator = TextSpan(text: ' · ', style: metaStyle);
    final spans = <InlineSpan>[
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Padding(
          padding: const EdgeInsets.only(right: 3),
          child: Icon(LucideIcons.clock, size: WpIconSize.xs, color: textMuted),
        ),
      ),
      TextSpan(
        text: timeLabel,
        style: TextStyle(fontSize: WpTypography.caption, color: textSecondary),
      ),
      separator,
      TextSpan(text: durationLabel, style: metaStyle),
      if (wordCount > 0) ...[
        separator,
        TextSpan(text: l10n.historyListWordCount(wordCount), style: metaStyle),
      ],
      if (language.isNotEmpty) ...[
        separator,
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: HistoryStatusChip(label: language.toUpperCase()),
        ),
      ],
      if (!isLocal) ...[
        separator,
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Icon(LucideIcons.cloud, size: WpIconSize.xs, color: textMuted),
        ),
      ],
    ];
    // Two lines, not one: the facts are what tell recordings apart, so a
    // narrow row wraps them rather than cutting off the duration or words.
    return Text.rich(
      TextSpan(children: spans),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _EntryTagChips extends StatelessWidget {
  const _EntryTagChips({required this.tags, this.onTagTap});

  final List<String> tags;
  final void Function(String tag)? onTagTap;

  @override
  Widget build(BuildContext context) {
    final textMuted = WpColors.textMuted;
    return Wrap(
      spacing: 4,
      runSpacing: 2,
      children: [
        for (final tag in tags.take(3))
          // loam-ignore: a11y-interactive-semantics – semantics provided in _EntryTagChipState.build
          _EntryTagChip(
            tag: tag,
            slot: categorySlotForTag(tag),
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

/// A tag chip, tinted in its tag's own category hue.
///
/// The hue is carried by the fill and the outline (*The Tint Ladder Rule*'s
/// 12 % and 30 % rungs) but never by the label: eight hues behind a 10px word
/// is eight contrast problems, and the tag's name already says which tag it is,
/// so the color is a second, redundant channel rather than the carrier.
class _EntryTagChip extends StatefulWidget {
  const _EntryTagChip({
    required this.tag,
    required this.slot,
    required this.onTap,
  });

  final String tag;
  final WpCategorySlot slot;
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
        color: widget.slot.chipFill(),
        border: Border.all(color: widget.slot.chipBorder()),
        borderRadius: WpRadius.borderSm,
      ),
      child: Text(
        '#${widget.tag}',
        style: TextStyle(
          fontSize: WpTypography.micro,
          color: WpColors.textSecondary,
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
