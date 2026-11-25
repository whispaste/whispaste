/// The search over Aufnahmen, Notizen and Textbausteine (#628): Cmd+K on
/// macOS, Ctrl+K on Windows and Linux, or "Search everywhere…" in the menu.
///
/// One field, the hits grouped by area below it, each with its excerpt and
/// the match marked. The arrow keys move through the hits while the caret
/// stays in the field, Enter opens the highlighted one at its place, Escape
/// closes. The highlighted hit is announced to screen readers, as in the
/// snippet chooser (#664): Flutter drops an invisible live region before it
/// reaches the platform's accessibility API.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../core/accessibility/announce.dart';
import '../../core/config/command_shortcut.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/navigation/page_state.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/dialog.dart';
import '../../widgets/wp_collection_list_item.dart';
import '../../widgets/wp_list_tile_surface.dart';
import '../../widgets/wp_search_field.dart';
import '../../widgets/wp_tag_chip.dart';
import 'data/providers.dart';

/// Binding that opens the search: Cmd+K on macOS, Ctrl+K elsewhere.
SingleActivator get contentSearchActivator =>
    commandActivator(LogicalKeyboardKey.keyK);

/// Waits this long after a keystroke before searching, so fast typing runs
/// one query instead of one per letter.
const kContentSearchDebounce = Duration(milliseconds: 150);

/// The name of [area] as the navigation shows it.
String contentSearchAreaLabel(L10n l10n, ContentSearchArea area) =>
    switch (area) {
      ContentSearchArea.recordings => l10n.navHistory,
      ContentSearchArea.notes => l10n.navNotes,
      ContentSearchArea.snippets => l10n.navSnippets,
    };

bool _open = false;

/// Opens the search dialog over [context]; a second request while it is
/// open does nothing. A picked hit is opened at its place.
Future<void> showContentSearch(BuildContext context, WidgetRef ref) async {
  if (_open) return;
  _open = true;
  try {
    final l10n = L10n.of(context);
    final hit = await showWpDialog<ContentSearchHit>(
      context: context,
      title: l10n.contentSearchTitle,
      size: WpDialogSize.wide,
      content: const ContentSearchPanel(),
      actions: [
        WpDialogAction<ContentSearchHit>(
          label: l10n.actionClose,
          testId: 'content-search-close',
          role: WpDialogActionRole.cancel,
        ),
      ],
    );
    if (hit == null || !context.mounted) return;
    // Open the hit once the dialog has faded out: while its route is still
    // leaving it hands focus back to the page below, which took the focus
    // (and so the visible selection) from the note editor (seen on macOS).
    await Future<void>.delayed(WpMotion.durationFor(context, WpMotion.smooth));
    await WidgetsBinding.instance.endOfFrame;
    if (!context.mounted) return;
    openContentSearchHit(ref.read, hit);
  } finally {
    _open = false;
  }
}

/// Opens the dialog whenever [contentSearchRequestProvider] fires. Sits in
/// the app shell, under the navigator; renders nothing.
class ContentSearchLauncher extends ConsumerWidget {
  const ContentSearchLauncher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<int>(contentSearchRequestProvider, (_, _) {
      unawaited(showContentSearch(context, ref));
    });
    return const SizedBox.shrink();
  }
}

/// The field and the grouped hits; pops the dialog with the picked hit.
class ContentSearchPanel extends ConsumerStatefulWidget {
  const ContentSearchPanel({super.key});

  @override
  ConsumerState<ContentSearchPanel> createState() => _ContentSearchPanelState();
}

class _ContentSearchPanelState extends ConsumerState<ContentSearchPanel> {
  final _controller = TextEditingController();
  late final FocusNode _focus = FocusNode(onKeyEvent: _onKey);
  final Map<String, GlobalKey> _rowKeys = {};
  Timer? _debounce;
  String _query = '';
  int _highlight = 0;

  /// The last answer, shown while the next one loads so the list does not
  /// flicker on every keystroke.
  ContentSearchResults _shown = ContentSearchResults.empty;
  String? _announced;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(kContentSearchDebounce, () {
      if (mounted) setState(() => _query = text.trim());
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final count = _shown.flat.length;
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
    final hit = _shown.flat[index];
    _announce(_spoken(L10n.of(context), hit));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _rowKeys[_keyOf(hit)]?.currentContext;
      if (ctx != null) {
        unawaited(Scrollable.ensureVisible(ctx, alignment: 0.5));
      }
    });
  }

  void _pick(ContentSearchHit hit) => Navigator.of(context).pop(hit);

  void _announce(String text) {
    if (text == _announced) return;
    _announced = text;
    announce(View.of(context), text, Directionality.of(context));
  }

  static String _keyOf(ContentSearchHit hit) => '${hit.area.name}-${hit.id}';

  String _titleOf(L10n l10n, ContentSearchHit hit) =>
      (hit.title?.trim().isNotEmpty ?? false)
      ? hit.title!.trim()
      : l10n.notesUntitled;

  String _textOf(ContentSearchHit hit) {
    final e = hit.excerpt;
    if (e == null) return hit.preview;
    return '${e.leadingCut ? '… ' : ''}${e.before}${e.match}${e.after}'
        '${e.trailingCut ? ' …' : ''}';
  }

  /// What a screen reader hears for a hit: area, title, excerpt and tags.
  String _spoken(L10n l10n, ContentSearchHit hit) {
    final text = _textOf(hit);
    final area = contentSearchAreaLabel(l10n, hit.area);
    final spoken = text.isEmpty
        ? '$area: ${_titleOf(l10n, hit)}'
        : '$area: ${_titleOf(l10n, hit)}, $text';
    if (hit.tags.isEmpty) return spoken;
    return '$spoken, ${hit.tags.map((t) => '#$t').join(' ')}';
  }

  /// Takes a new answer: the highlight goes back to the first hit, and the
  /// count is announced once.
  void _take(ContentSearchResults results, L10n l10n) {
    if (identical(results, _shown)) return;
    _shown = results;
    _highlight = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _query.isEmpty) return;
      final count = results.flat.length;
      _announce(
        count == 0
            ? l10n.contentSearchNoResults
            : l10n.contentSearchResultCount(count),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final async = ref.watch(contentSearchProvider(_query));
    if (async case AsyncData(:final value)) _take(value, l10n);
    final results = _query.isEmpty ? ContentSearchResults.empty : _shown;
    final flat = results.flat;
    if (_highlight >= flat.length) _highlight = 0;
    final failed = async.hasError && !async.isLoading;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WpSearchField(
          controller: _controller,
          focusNode: _focus,
          hintText: l10n.contentSearchFieldHint,
          semanticsLabel: l10n.contentSearchFieldLabel,
          variant: WpSearchFieldVariant.outlined,
          autofocus: true,
          testId: 'content-search-field',
          onChanged: _onChanged,
          onSubmitted: (_) {
            if (flat.isNotEmpty) _pick(flat[_highlight]);
          },
        ),
        const SizedBox(height: WpSpacing.sm),
        if (results.withheld)
          _Note(
            testId: 'content-search-withheld',
            text: l10n.contentSearchWithheld,
          ),
        if (failed)
          _Note(testId: 'content-search-error', text: l10n.contentSearchFailed)
        else if (_query.isEmpty)
          _Note(testId: 'content-search-hint', text: l10n.contentSearchHint)
        else if (flat.isEmpty && async.hasValue)
          _Note(
            testId: 'content-search-empty',
            text: l10n.contentSearchNoResults,
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final group in results.groups) ...[
                    _GroupHeader(
                      area: group.area,
                      label: contentSearchAreaLabel(l10n, group.area),
                      count: group.more
                          ? l10n.contentSearchCountMore(group.total)
                          : '${group.total}',
                    ),
                    for (final hit in group.shown)
                      _HitRow(
                        key: _rowKeys.putIfAbsent(_keyOf(hit), GlobalKey.new),
                        hit: hit,
                        title: _titleOf(l10n, hit),
                        semanticsLabel: _spoken(l10n, hit),
                        highlighted:
                            flat.isNotEmpty && identical(flat[_highlight], hit),
                        onTap: () => _pick(hit),
                      ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.testId, required this.text});

  final String testId;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: testId,
      child: Padding(
        key: ValueKey(testId),
        padding: const EdgeInsets.symmetric(vertical: WpSpacing.sm),
        child: Text(
          text,
          style: TextStyle(
            color: WpColors.textMuted,
            fontSize: WpTypography.small,
          ),
        ),
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.area,
    required this.label,
    required this.count,
  });

  final ContentSearchArea area;
  final String label;
  final String count;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: 'content-search-group-${area.name}',
      header: true,
      label: '$label, $count',
      excludeSemantics: true,
      child: Padding(
        key: ValueKey('content-search-group-${area.name}'),
        padding: const EdgeInsets.only(top: WpSpacing.md, bottom: WpSpacing.xs),
        child: Text(
          '$label · $count',
          style: TextStyle(
            color: WpColors.textMuted,
            fontSize: WpTypography.small,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _HitRow extends StatefulWidget {
  const _HitRow({
    super.key,
    required this.hit,
    required this.title,
    required this.semanticsLabel,
    required this.highlighted,
    required this.onTap,
  });

  final ContentSearchHit hit;
  final String title;
  final String semanticsLabel;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  State<_HitRow> createState() => _HitRowState();
}

class _HitRowState extends State<_HitRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final hit = widget.hit;
    final id = 'content-search-hit-${hit.area.name}-${hit.id}';
    final locale = Localizations.localeOf(context).toString();
    final date = DateFormat.yMMMd(locale).format(hit.changedAt);
    return Semantics(
      identifier: id,
      button: true,
      selected: widget.highlighted,
      label: widget.semanticsLabel,
      excludeSemantics: true,
      onTap: widget.onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          key: ValueKey(id),
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
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: WpColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: WpSpacing.sm),
                    Text(
                      date,
                      style: TextStyle(
                        color: WpColors.textMuted,
                        fontSize: WpTypography.small,
                      ),
                    ),
                  ],
                ),
                _Excerpt(hit: hit),
                if (hit.tags.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: WpSpacing.xxs),
                    child: WpTagChipRow(
                      key: ValueKey('$id-tags'),
                      names: hit.tags,
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

/// Two lines of the text: the excerpt with the match in the marker tokens of
/// the notes hit list (#872), or the start of the text.
class _Excerpt extends StatelessWidget {
  const _Excerpt({required this.hit});

  final ContentSearchHit hit;

  @override
  Widget build(BuildContext context) {
    final e = hit.excerpt;
    if (e == null) {
      if (hit.preview.isEmpty) return const SizedBox.shrink();
      return Text(
        hit.preview,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: WpCollectionListItem.previewStyle(),
      );
    }
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: '${e.leadingCut ? '… ' : ''}${e.before}'),
          TextSpan(
            text: e.match,
            style: TextStyle(
              color: WpColors.highlightText,
              backgroundColor: WpColors.highlightSoft,
              fontWeight: FontWeight.w600,
            ),
          ),
          TextSpan(text: '${e.after}${e.trailingCut ? ' …' : ''}'),
        ],
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: WpCollectionListItem.previewStyle(),
    );
  }
}
