// Insert a Textbaustein from inside an editor (#664).
//
// The systemwide snippet picker is a native overlay that types into the
// foreground app; inside the app's own editors (notes, transcripts, the
// snippet editor itself) it would type into the very field that opened it
// through the OS, losing the selection and the undo step. So the editors get
// this small in-app chooser instead: search, arrow keys, Enter — and the
// pick lands at the caret through the editor's own controller.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/accessibility/announce.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/dialog.dart';
import '../../../widgets/wp_list_tile_surface.dart';
import '../../../widgets/wp_search_field.dart';
import '../snippet_item.dart';

/// The snippets the chooser lists for [query]: favourites first, then the
/// library order; a non-empty query keeps the ones whose title or body
/// contains it, ignoring case.
List<SnippetItem> filterSnippetsForInsert(
  List<SnippetItem> items,
  String query,
) {
  final q = query.trim().toLowerCase();
  final ordered = favouritesFirst(items);
  if (q.isEmpty) return ordered;
  return [
    for (final s in ordered)
      if (s.title.toLowerCase().contains(q) || s.body.toLowerCase().contains(q))
        s,
  ];
}

/// The start of [body] as the chooser speaks it: whitespace folded and cut
/// after [maxChars] at a word boundary, like the one-line preview on screen.
/// A long snippet would otherwise be read out whole on every arrow key.
String spokenSnippetPreview(String body, {int maxChars = 80}) {
  final text = body.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.length <= maxChars) return text;
  final cut = text.lastIndexOf(' ', maxChars);
  return '${text.substring(0, cut > 0 ? cut : maxChars)}…';
}

/// Opens the chooser over [items] and returns the picked snippet, `null`
/// when the dialog is dismissed. The library lookup and the caret insertion
/// live in `snippets_page.dart` (`insertSnippetAtCursor`), so this file stays
/// free of the page and the snippet editor can use it without an import
/// cycle.
Future<SnippetItem?> pickSnippetForInsert(
  BuildContext context,
  List<SnippetItem> items,
) {
  final l10n = L10n.of(context);
  return showWpDialog<SnippetItem>(
    context: context,
    title: l10n.snippetInsertDialogTitle,
    content: _SnippetInsertChooser(items: items),
    actions: [
      WpDialogAction<SnippetItem>(
        label: l10n.actionCancel,
        testId: 'snippet-insert-cancel',
        role: WpDialogActionRole.cancel,
      ),
    ],
  );
}

class _SnippetInsertChooser extends StatefulWidget {
  const _SnippetInsertChooser({required this.items});

  final List<SnippetItem> items;

  @override
  State<_SnippetInsertChooser> createState() => _SnippetInsertChooserState();
}

class _SnippetInsertChooserState extends State<_SnippetInsertChooser> {
  final _query = TextEditingController();
  late final FocusNode _searchFocus = FocusNode(onKeyEvent: _onSearchKey);
  final Map<String, GlobalKey> _rowKeys = {};
  int _highlight = 0;

  List<SnippetItem> get _visible =>
      filterSnippetsForInsert(widget.items, _query.text);

  @override
  void dispose() {
    _query.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// Up/Down move the highlight while typing stays in the search field, so
  /// the whole chooser works without leaving the keyboard's home row.
  KeyEventResult _onSearchKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final count = _visible.length;
    if (count == 0) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      _moveHighlight((_highlight + 1) % count);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _moveHighlight((_highlight - 1 + count) % count);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _moveHighlight(int index) {
    setState(() => _highlight = index);
    _announceStatus();
    final id = _visible[index].id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _rowKeys[id]?.currentContext;
      if (ctx != null) {
        unawaited(Scrollable.ensureVisible(ctx, alignment: 0.5));
      }
    });
  }

  void _pick(SnippetItem item) => Navigator.of(context).pop(item);

  /// What a screen reader hears for the current state: the highlighted
  /// snippet's title and the start of its text, or why the list is empty.
  String _statusText(L10n l10n, List<SnippetItem> visible) {
    if (visible.isEmpty) {
      return widget.items.isEmpty
          ? l10n.snippetInsertEmpty
          : l10n.snippetInsertNoMatch;
    }
    final item = visible[_highlight.clamp(0, visible.length - 1)];
    final preview = spokenSnippetPreview(item.body);
    return preview.isEmpty ? item.title : '${item.title}, $preview';
  }

  /// The last text sent by [_announceStatus], so typing that keeps the same
  /// highlight stays quiet.
  String? _announced;

  /// Focus stays in search while the arrow keys move the highlight, so the
  /// active result is spoken as an announcement. A live region does not do
  /// this: Flutter drops an invisible node before it reaches AT-SPI, UIA or
  /// NSAccessibility (checked with another app on Ubuntu, #664).
  void _announceStatus() {
    final l10n = L10n.of(context);
    final text = _statusText(l10n, _visible);
    if (text == _announced) return;
    _announced = text;
    announce(View.of(context), text, Directionality.of(context));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final visible = _visible;
    if (_highlight >= visible.length) _highlight = 0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WpSearchField(
          controller: _query,
          focusNode: _searchFocus,
          hintText: l10n.snippetInsertSearchHint,
          variant: WpSearchFieldVariant.outlined,
          autofocus: true,
          testId: 'snippet-insert-search',
          onChanged: (_) {
            setState(() => _highlight = 0);
            _announceStatus();
          },
          onSubmitted: (_) {
            if (visible.isNotEmpty) _pick(visible[_highlight]);
          },
        ),
        const SizedBox(height: WpSpacing.sm),
        if (visible.isEmpty)
          Padding(
            key: const ValueKey('snippet-insert-empty'),
            padding: const EdgeInsets.symmetric(vertical: WpSpacing.md),
            child: Text(
              widget.items.isEmpty
                  ? l10n.snippetInsertEmpty
                  : l10n.snippetInsertNoMatch,
              style: TextStyle(
                color: WpColors.textMuted,
                fontSize: WpTypography.small,
              ),
            ),
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < visible.length; i++)
                    _SnippetInsertRow(
                      key: _rowKeys.putIfAbsent(visible[i].id, GlobalKey.new),
                      item: visible[i],
                      highlighted: i == _highlight,
                      onTap: () => _pick(visible[i]),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _SnippetInsertRow extends StatefulWidget {
  const _SnippetInsertRow({
    super.key,
    required this.item,
    required this.highlighted,
    required this.onTap,
  });

  final SnippetItem item;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  State<_SnippetInsertRow> createState() => _SnippetInsertRowState();
}

class _SnippetInsertRowState extends State<_SnippetInsertRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final preview = item.body.replaceAll(RegExp(r'\s+'), ' ').trim();
    return Semantics(
      identifier: 'snippet-insert-item-${item.id}',
      button: true,
      selected: widget.highlighted,
      label: item.title,
      hint: preview,
      excludeSemantics: true,
      onTap: widget.onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          key: ValueKey('snippet-insert-item-${item.id}'),
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: WpListTileSurface(
            variant: WpListTileVariant.panel,
            isHovered: _hovered,
            isFocused: widget.highlighted,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: WpColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (preview.isNotEmpty)
                  Text(
                    preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: WpColors.textMuted,
                      fontSize: WpTypography.small,
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
