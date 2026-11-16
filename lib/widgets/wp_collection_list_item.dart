import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import 'wp_context_menu.dart';
import 'wp_list_item_content.dart';
import 'wp_list_tile_surface.dart';

// ---------------------------------------------------------------------------
// WpCollectionListItem — the one item row of the collection lists
// (recordings, notes, snippets; #1498).
//
// [WpListTileSurface] fixed the envelope and [WpListItemContent] the layout,
// but each list still wired them up itself: its own hover flag, its own rule
// for when the actions show, its own meta tint, its own title and preview
// styles, its own right-click menu. Those copies had started to drift (the
// recordings meta line never tinted, the snippet meta tinted on hover but not
// on the open row, the title tracking differed). This widget owns all of it;
// a list hands in data and slots only.
//
// Rules owned here, the same in every list:
// * Interaction: pointer cursor, tap, right-click opens [contextMenu] through
//   [showWpContextMenu].
// * Actions show on hover, keyboard focus, the arrow cursor ([isFocused]) or
//   the open item ([isOpen]); [revealActions] false keeps them hidden
//   (multi-select). While hidden, a favourite shows the resting star mark.
// * Meta tint: the meta line is muted at rest and secondary on any tinted
//   state, because muted text falls below 4.5:1 on the hover and selection
//   washes. [meta] receives the colour to use (null = the muted default).
// * Title and preview styles: [titleStyle], [previewStyle],
//   [WpCollectionListItemTitle], [WpCollectionListItemPreview].
// ---------------------------------------------------------------------------

/// Shared item row of the collection lists. See the library comment.
class WpCollectionListItem extends StatefulWidget {
  const WpCollectionListItem({
    super.key,
    required this.typeIcon,
    required this.title,
    required this.actions,
    required this.onTap,
    required this.semanticsIdentifier,
    this.contentKey,
    this.leading,
    this.badges = const [],
    this.isFavourite = false,
    this.favouriteMarkKey,
    this.favouriteMarkLabel,
    this.marks = const [],
    this.preview,
    this.previewSemanticsLabel,
    this.meta,
    this.footer,
    this.isFocused = false,
    this.isHighlighted = false,
    this.isSelected = false,
    bool? isOpen,
    this.revealActions = true,
    this.contextMenu,
    this.focusable = false,
    this.onDeleteKey,
    this.semanticsLabel,
    this.semanticsHint,
    this.semanticsSelected,
    this.semanticsFocused,
    this.customSemanticsActions,
  }) : isOpen = isOpen ?? isSelected;

  /// Kind glyph of the item.
  final IconData typeIcon;

  /// The one-line title, usually a [WpCollectionListItemTitle].
  final Widget title;

  /// The action cluster (a `WpListItemActions`) for the given visibility.
  final Widget Function(bool visible) actions;

  final VoidCallback onTap;

  /// Key of the inner [WpListItemContent].
  final Key? contentKey;

  /// Slot before the glyph (multi-select checkbox).
  final Widget? leading;

  /// State badges right after the title (interactive, draft).
  final List<Widget> badges;

  /// The item is a favourite: shows the resting star mark while the actions
  /// are hidden.
  final bool isFavourite;
  final Key? favouriteMarkKey;
  final String? favouriteMarkLabel;

  /// Permanent marks after the star mark (the quick-note bolt).
  final List<Widget> marks;

  final Widget? preview;
  final String? previewSemanticsLabel;

  /// Builds the meta line with the colour for the current state (null = the
  /// muted default). Usually a `WpListItemMeta`.
  final Widget Function(Color? color)? meta;
  final Widget? footer;

  /// The list's arrow cursor stands on this row.
  final bool isFocused;

  /// A just-created item: drawn with the focus look for a moment, without
  /// revealing the actions or tinting the meta line (that stays tied to real
  /// hover, focus and the cursor).
  final bool isHighlighted;

  /// The row is drawn selected: the open item or a checked row.
  final bool isSelected;

  /// The item is the one in the detail: keeps the actions revealed. Defaults
  /// to [isSelected].
  final bool isOpen;

  /// False hides the actions in every state (multi-select).
  final bool revealActions;

  /// Entries of the right-click menu; null means no menu.
  final List<WpContextMenuEntry> Function()? contextMenu;

  /// The row takes keyboard focus itself (Tab), Enter/Space activate it.
  final bool focusable;

  /// Delete/Backspace while focus sits inside the row.
  final VoidCallback? onDeleteKey;

  /// Stable test id of the row (`<screen>-row-<id>`), required so every
  /// collection row is addressable the same way (#1498).
  final String semanticsIdentifier;
  final String? semanticsLabel;
  final String? semanticsHint;

  /// Defaults to [isSelected].
  final bool? semanticsSelected;
  final bool? semanticsFocused;
  final Map<CustomSemanticsAction, VoidCallback>? customSemanticsActions;

  /// Title style of every item row.
  static TextStyle titleStyle() => TextStyle(
    fontSize: WpTypography.subheading,
    fontWeight: FontWeight.w600,
    color: WpColors.textPrimary,
  );

  /// Preview style of every item row. The gap to the title belongs to
  /// [WpListItemContent], so the preview carries no padding of its own.
  static TextStyle previewStyle() => TextStyle(
    fontSize: WpTypography.body,
    color: WpColors.textSecondary,
    height: 1.35,
  );

  @override
  State<WpCollectionListItem> createState() => _WpCollectionListItemState();
}

class _WpCollectionListItemState extends State<WpCollectionListItem> {
  bool _isHovered = false;
  bool _hasFocusHighlight = false;

  bool get _isActive => _isHovered || _hasFocusHighlight || widget.isFocused;

  void _setHovered(bool value) {
    if (_isHovered == value) return;
    setState(() => _isHovered = value);
  }

  void _openMenu(Offset globalPosition) {
    final build = widget.contextMenu;
    if (build == null) return;
    showWpContextMenu(
      context,
      globalPosition: globalPosition,
      entries: build(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final actionsVisible = widget.revealActions && (_isActive || widget.isOpen);
    final tinted = _isActive || widget.isSelected;
    final customActions = widget.customSemanticsActions;

    Widget row = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: GestureDetector(
        onTap: widget.onTap,
        onSecondaryTapUp: widget.contextMenu == null
            ? null
            : (details) => _openMenu(details.globalPosition),
        child: WpListTileSurface(
          variant: WpListTileVariant.card,
          isHovered: _isHovered,
          isFocused:
              _hasFocusHighlight || widget.isFocused || widget.isHighlighted,
          isSelected: widget.isSelected,
          child: WpListItemContent(
            key: widget.contentKey,
            typeIcon: widget.typeIcon,
            leading: widget.leading,
            title: widget.title,
            titleTrailing: [
              ...widget.badges,
              if (widget.isFavourite && !actionsVisible)
                WpListItemStarMark(
                  key: widget.favouriteMarkKey,
                  semanticsLabel: widget.favouriteMarkLabel,
                ),
              ...widget.marks,
            ],
            actions: widget.actions(actionsVisible),
            preview: widget.preview,
            previewSemanticsLabel: widget.previewSemanticsLabel,
            meta: widget.meta?.call(tinted ? WpColors.textSecondary : null),
            footer: widget.footer,
          ),
        ),
      ),
    );

    if (widget.focusable) {
      row = FocusableActionDetector(
        onShowFocusHighlight: (value) {
          if (_hasFocusHighlight == value) return;
          setState(() => _hasFocusHighlight = value);
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap();
              return null;
            },
          ),
        },
        child: row,
      );
    }

    row = Semantics(
      identifier: widget.semanticsIdentifier,
      label: widget.semanticsLabel,
      hint: widget.semanticsHint,
      button: true,
      selected: widget.semanticsSelected ?? widget.isSelected,
      focused: widget.semanticsFocused,
      customSemanticsActions: customActions == null || customActions.isEmpty
          ? null
          : customActions,
      child: row,
    );

    if (widget.onDeleteKey case final onDelete?) {
      // Scoped to the row: the bindings only fire while focus sits inside
      // it, so a sibling search field keeps Backspace for editing text.
      row = CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.delete): onDelete,
          const SingleActivator(LogicalKeyboardKey.backspace): onDelete,
        },
        child: row,
      );
    }
    return row;
  }
}

/// The one-line title of an item row, in [WpCollectionListItem.titleStyle].
class WpCollectionListItemTitle extends StatelessWidget {
  const WpCollectionListItemTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: WpCollectionListItem.titleStyle(),
    );
  }
}

/// The preview of an item row, in [WpCollectionListItem.previewStyle].
class WpCollectionListItemPreview extends StatelessWidget {
  const WpCollectionListItemPreview(this.text, {super.key, this.maxLines = 2});

  final String text;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: WpCollectionListItem.previewStyle(),
    );
  }
}
