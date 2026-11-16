import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/wp_app_icon.dart';
import '../../../widgets/wp_focus_ring.dart';
import '../../../widgets/wp_collection_list_item.dart';
import '../../../widgets/wp_context_menu.dart';
import '../../../widgets/wp_list_item_content.dart';
import '../../../widgets/wp_favourite_star.dart';
import '../../../widgets/wp_row_action.dart';
import '../../../widgets/wp_row_checkbox.dart';

import 'package:whispaste/core/data/database.dart';

import 'highlighted_text.dart';
import 'history_helpers.dart';
import '../../../core/data/content_metadata_providers.dart';

// ---------------------------------------------------------------------------
// History entry row — WhatsApp/ChatGPT/Discord-inspired
// ---------------------------------------------------------------------------

class HistoryEntryRow extends ConsumerStatefulWidget {
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
  ConsumerState<HistoryEntryRow> createState() => _HistoryEntryRowState();
}

class _HistoryEntryRowState extends ConsumerState<HistoryEntryRow> {
  // Assigned tags are separate from parsed inline hashtags. Decode them only
  // when the row changes, not on every hover. Text counters use the index.
  late List<String> _entryTags = _computeEntryTags(widget.entry);
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
      _entryTags = _computeEntryTags(widget.entry);
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

  /// Right-click menu: the hover buttons plus Duplicate, which has no button
  /// of its own (one action set per row: Copy, Star, Delete; #1498), so a row
  /// can be handled without hovering its trailing icons (UIA-HIS-32).
  List<WpContextMenuEntry> _contextMenu() {
    final l10n = L10n.of(context);
    final entry = widget.entry;
    if (widget.isTrashView) {
      return [
        if (widget.onRestore case final onRestore?)
          WpContextMenuEntry(
            icon: LucideIcons.undo2,
            label: l10n.historyRestore,
            onSelected: onRestore,
          ),
        WpContextMenuEntry(
          icon: LucideIcons.trash2,
          label: l10n.historyDeleteForever,
          onSelected: widget.onDelete,
          destructive: true,
        ),
      ];
    }
    return [
      WpContextMenuEntry(
        icon: LucideIcons.copy,
        label: l10n.historyCopyText,
        onSelected: widget.onCopy,
      ),
      WpContextMenuEntry(
        icon: LucideIcons.star,
        label: entry.pinned ? l10n.historyUnpin : l10n.historyPinToTop,
        onSelected: widget.onPin,
      ),
      if (widget.onDuplicate case final onDuplicate?)
        WpContextMenuEntry(
          icon: LucideIcons.files,
          label: l10n.actionDuplicate,
          onSelected: onDuplicate,
        ),
      WpContextMenuEntry(
        icon: LucideIcons.trash2,
        label: l10n.actionDelete,
        onSelected: widget.onDelete,
        destructive: true,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final id = entry.id;
    final wordCount =
        ref
            .watch(
              contentMetadataProvider((kind: ContentKind.recording, id: id)),
            )
            .value
            ?.wordCount ??
        0;
    final l10n = L10n.of(context);
    final duplicate = widget.isTrashView || widget.multiSelectMode
        ? null
        : widget.onDuplicate;
    final title = entry.title.isNotEmpty
        ? entry.title
        : l10n.historyUntitledRecording;
    // A short recording's generated title is its whole text: printing it a
    // second time as preview only costs a line (#1498).
    final showPreview = WpListItemContent.previewDiffers(title, entry.content);

    return WpCollectionListItem(
      contentKey: ValueKey('history-row-content-$id'),
      semanticsIdentifier: 'history-row-$id',
      // House idiom, group variant (`no_double_announcement_test.dart`): the
      // row keeps its `label:` and the rendered title is hidden with
      // ExcludeSemantics below, because this subtree holds several interactive
      // nodes (checkbox, three row actions, tag chips). MergeSemantics — the
      // other permitted shape — would swallow all of them into one node.
      semanticsLabel: title,
      // `selected:` follows the arrow cursor, not the detail-panel selection.
      // The list holds a single Focus node and the arrow keys move nothing but
      // an optical highlight, so without this flag a screen reader reported no
      // change at all while the user arrowed through the list.
      //
      // Exactly one row may report selected at a time in single-select mode,
      // which is why this is not `isSelected || isFocused`: while arrowing
      // away from a clicked row the cursor — the row Enter and Delete will act
      // on — is the one worth announcing. Inside multi-select the cursor is
      // suppressed and `isSelected` carries the checked state, so the flag
      // reports the checked rows instead.
      semanticsSelected: widget.multiSelectMode
          ? widget.isSelected
          : widget.isFocused,
      semanticsFocused: widget.isFocused,
      // Duplicate lives in the context menu only; this keeps it reachable for
      // screen readers, which cannot open a right-click menu.
      customSemanticsActions: duplicate == null
          ? null
          : {CustomSemanticsAction(label: l10n.actionDuplicate): duplicate},
      typeIcon: historyAvatarIcon,
      leading: widget.multiSelectMode
          ? WpRowCheckbox(value: widget.isChecked, onChanged: widget.onTap)
          : null,
      title: ExcludeSemantics(
        // Excluded because the row's semantics already carry this exact
        // string as its label; without this the title was announced twice.
        // Preview and metadata stay announced, they are content.
        child: HighlightedText(
          text: title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: WpCollectionListItem.titleStyle(),
        ),
      ),
      // A pinned recording keeps its star visible at rest: the star is the
      // row's only carrier of that state. Not in the trash, where Star is no
      // action either.
      isFavourite: entry.pinned && !widget.isTrashView,
      favouriteMarkKey: ValueKey('history-favourite-mark-$id'),
      favouriteMarkLabel: l10n.listItemFavouriteMark,
      actions: (visible) => _buildActions(l10n, visible),
      // Two lines in a split panel, one in the overview, where the row is
      // wide enough to show more on one line.
      preview: showPreview
          ? HighlightedText(
              key: ValueKey('history-row-preview-$id'),
              text: entry.content,
              maxLines: widget.inSplitView ? 2 : 1,
              overflow: TextOverflow.ellipsis,
              style: WpCollectionListItem.previewStyle(),
            )
          : null,
      // The preview Text would read the whole recording; the generated
      // title already is its opening, so the row says title and meta (#1498).
      previewSemanticsLabel: WpListItemContent.spokenPreview(
        title,
        entry.content,
      ),
      meta: (color) => _EntryMetaRow(
        key: ValueKey('history-row-meta-$id'),
        color: color,
        timeLabel: _timeLabel,
        durationLabel: _durationLabel,
        wordCount: wordCount,
        language: entry.language,
        isLocal: entry.isLocal,
        targetApp: entry.targetApp?.trim(),
      ),
      footer: _entryTags.isEmpty
          ? null
          : _EntryTagChips(tags: _entryTags, onTagTap: widget.onTagTap),
      isFocused: widget.isFocused,
      isSelected: widget.isSelected,
      // Multi-select hides the row actions and the right-click menu: the
      // row is a checkbox target there.
      revealActions: !widget.multiSelectMode,
      onTap: widget.onTap,
      contextMenu: widget.multiSelectMode ? null : _contextMenu,
    );
  }

  /// In the trash only restore and permanent delete make sense (UIA-HIS-09).
  /// Otherwise the shared set: Copy, Star, Delete. Duplicate is in the
  /// context menu and the row's custom semantics actions (#1498).
  Widget _buildActions(L10n l10n, bool visible) {
    final entry = widget.entry;
    final id = entry.id;
    final restore = widget.onRestore;
    if (widget.isTrashView && restore != null) {
      return WpListItemActions.trash(
        visible: visible,
        restore: WpRowAction(
          key: ValueKey('history-restore-$id'),
          icon: LucideIcons.undo2,
          tooltip: l10n.historyRestore,
          onTap: restore,
          dense: true,
          testId: 'history-restore-$id',
        ),
        delete: WpRowAction(
          key: ValueKey('history-delete-forever-$id'),
          icon: LucideIcons.trash2,
          tooltip: l10n.historyDeleteForever,
          onTap: widget.onDelete,
          isDestructive: true,
          dense: true,
          testId: 'history-delete-forever-$id',
        ),
      );
    }
    return WpListItemActions(
      visible: visible,
      copy: WpRowAction(
        key: ValueKey('history-copy-$id'),
        icon: LucideIcons.copy,
        tooltip: l10n.historyCopyText,
        onTap: widget.onCopy,
        dense: true,
        testId: 'history-copy-$id',
      ),
      star: WpFavouriteStar(
        key: ValueKey('history-pin-$id'),
        isFavourite: entry.pinned,
        onToggle: widget.onPin,
        testId: 'history-pin-$id',
      ),
      delete: WpRowAction(
        key: ValueKey('history-delete-$id'),
        icon: LucideIcons.trash2,
        tooltip: l10n.actionDelete,
        onTap: widget.onDelete,
        isDestructive: true,
        dense: true,
        testId: 'history-delete-$id',
      ),
    );
  }
}

class _EntryMetaRow extends ConsumerWidget {
  const _EntryMetaRow({
    super.key,
    this.color,
    required this.timeLabel,
    required this.durationLabel,
    required this.wordCount,
    required this.language,
    required this.isLocal,
    this.targetApp,
  });

  /// Base colour from the row's state; null = the muted default.
  final Color? color;
  final String timeLabel;
  final String durationLabel;
  final int wordCount;
  final String language;
  final bool isLocal;

  /// The app the text went to; null or empty shows no app.
  final String? targetApp;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final textMuted = WpColors.textMuted;
    final app = targetApp ?? '';
    final hasApp = app.isNotEmpty;
    final appName = hasApp ? watchAppName(ref, app).trim() : '';
    // Order is priority: the line is one line and ellipsizes at the end, so
    // time and app (what tells recordings apart) come first, the rest gives
    // way on a narrow panel. Language is plain text, not a chip (#1498).
    // Facts the entry does not have are left out entirely, separator
    // included: an unknown target app used to leave an empty slot
    // ("18:08 ·   · 0s"), the neutral tile carried no information.
    final segments = <List<InlineSpan>?>[
      [
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.only(right: WpSpacing.xxs),
            child: Icon(
              LucideIcons.clock,
              size: WpIconSize.xs,
              color: textMuted,
            ),
          ),
        ),
        TextSpan(
          text: timeLabel,
          style: TextStyle(color: WpColors.textSecondary),
        ),
      ],
      if (appName.isNotEmpty)
        [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.only(right: WpSpacing.xxs),
              child: WpAppIcon(
                key: const ValueKey('history-entry-app-icon'),
                identifier: app,
                size: WpIconSize.xs,
              ),
            ),
          ),
          TextSpan(text: appName),
        ],
      [TextSpan(text: durationLabel)],
      [TextSpan(text: language.toUpperCase())],
      if (wordCount > 0) [TextSpan(text: l10n.historyListWordCount(wordCount))],
      if (!isLocal)
        [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Icon(
              LucideIcons.cloud,
              size: WpIconSize.xs,
              color: textMuted,
            ),
          ),
        ],
    ];
    return WpListItemMeta.segments(segments: segments, color: color);
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
            style: TextStyle(fontSize: WpTypography.caption, color: textMuted),
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
          fontSize: WpTypography.caption,
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
