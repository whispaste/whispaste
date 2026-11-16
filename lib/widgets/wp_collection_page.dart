/// The page family for collections: Recordings, Notes and Snippets
/// (concept: `internal-notes`, #919).
///
/// Two shared parts, one widget each and without per-page variants:
///
/// - [WpCollectionPage]: the frame with fixed slots from top to bottom:
///   selection bar, notices, toolbar, then the list/detail body (a
///   `WpCollectionSplit`). It also owns the one search shortcut (Cmd/Ctrl+F).
/// - [WpCollectionToolbar]: the head, one row with fixed places: search,
///   active-filter marks, the filter popover, status, view tools, further
///   ways to add (import) and the primary "new" action. Pages only differ in the filters they offer.
///
/// A page fills the slots with its own content; where a control sits is
/// decided here, once, so the three pages cannot drift apart again.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/config/command_shortcut.dart';
import '../core/theme/tokens.dart';
import 'filter_chip_scroller.dart';
import 'page_shell.dart';
import 'wp_collection_filters.dart';

export 'wp_collection_filters.dart' show WpActiveFilter, WpFilterSection;

/// True on a short window or at text scale 2.0 (UX-091). The collection head
/// then keeps only what it needs: while entries are selected the selection
/// bar takes the toolbar's place, so the list keeps its room.
bool wpCollectionHeadIsShort(BuildContext context) =>
    MediaQuery.sizeOf(context).height < WpCollectionPage.shortWindowHeight ||
    MediaQuery.textScalerOf(context).scale(1) >= 2.0;

/// Frame of a collection page (Recordings, Notes, Snippets).
///
/// Landmarks carry the stable ids `<screenId>-page`, `<screenId>-toolbar`
/// (via [WpCollectionToolbar]) and `<screenId>-list-area`.
class WpCollectionPage extends StatelessWidget {
  const WpCollectionPage({
    super.key,
    required this.screenId,
    required this.toolbar,
    required this.body,
    this.searchFocusNode,
    this.selectionBar,
    this.notices = const [],
  });

  /// Window height below which the head counts as short. The app minimum is
  /// 716 px, so the short mode is reachable on every system.
  static const double shortWindowHeight = 780;

  /// Prefix of every landmark id, e.g. `history`.
  final String screenId;

  /// The page head, normally a [WpCollectionToolbar].
  final Widget toolbar;

  /// The list and detail area, normally a `WpCollectionSplit`. Fills the rest.
  final Widget body;

  /// Receives the focus on Cmd/Ctrl+F.
  final FocusNode? searchFocusNode;

  /// The batch action bar, or null while nothing is selected.
  final Widget? selectionBar;

  /// Status rows, page notices and banners, in this order, above the toolbar.
  final List<Widget> notices;

  @override
  Widget build(BuildContext context) {
    final selecting = selectionBar != null;
    final hideToolbar = selecting && wpCollectionHeadIsShort(context);
    final focusNode = searchFocusNode;
    return WpPageShell(
      scrollable: false,
      padding: EdgeInsets.zero,
      child: Semantics(
        identifier: '$screenId-page',
        container: true,
        explicitChildNodes: true,
        child: CallbackShortcuts(
          bindings: <ShortcutActivator, VoidCallback>{
            if (focusNode != null)
              commandActivator(LogicalKeyboardKey.keyF): focusNode.requestFocus,
          },
          child: Focus(
            child: Column(
              children: [
                // Everything above the list takes its content height and never
                // scrolls: the search stays in view and the head has one scroll
                // owner or none (UX-097, UX-098).
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ?selectionBar,
                    ...notices,
                    if (!hideToolbar) toolbar,
                  ],
                ),
                Expanded(
                  key: ValueKey('$screenId-list-area'),
                  child: Semantics(
                    identifier: '$screenId-list-area',
                    container: true,
                    explicitChildNodes: true,
                    child: body,
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

/// Head of a collection page: one row with fixed places (#1201).
///
/// ```
/// [ search ····· ] [ marks ] [ filter ] [ status ] [ tools ] [ add ] [ new ]
///   search extras (suggestions while typing, temporary)
/// ```
///
/// Search and filter take one row on every page, at 800 px and at text scale
/// 1.3 too. The page's filters live in one popover behind the filter button
/// ([filterSections]); what is active shows as compact, removable marks
/// ([activeFilters]) next to the search, so the state stays visible without
/// a second chip row. Below [inlineToolsMinWidth] the [tools] collapse into
/// [toolsOverflow], one button on the same row; [addActions] and
/// [primaryAction] always stay inline. Every icon control of the row is the
/// bordered `WpIconButton` (44 px, never the ghost), so the row reads as one
/// set (#1498). Paddings are directional, so the order mirrors under RTL.
class WpCollectionToolbar extends StatelessWidget {
  const WpCollectionToolbar({
    super.key,
    required this.screenId,
    required this.search,
    this.primaryAction,
    this.addActions = const [],
    this.searchExtras = const [],
    this.filterSections = const [],
    this.activeFilters = const [],
    this.status = const [],
    this.tools = const [],
    this.toolsOverflow,
  });

  /// Row width from which [tools] stand inline instead of [toolsOverflow].
  /// The search shares the row, so it keeps a usable width up to here.
  static const double inlineToolsMinWidth = 880;

  /// Share of the row the marks may take before they scroll sideways.
  static const double marksMaxShare = 0.3;

  /// Share of the row the status group may take; longer text ellipsizes.
  static const double statusMaxShare = 0.22;

  /// Prefix of the landmark id `<screenId>-toolbar`.
  final String screenId;

  /// The search field. Takes all width the row leaves.
  final Widget search;

  /// The page's one "new" action, at the end of the row.
  final Widget? primaryAction;

  /// Further ways to add to the collection (Recordings: import audio files),
  /// grouped with [primaryAction] right before it. They never collapse into
  /// [toolsOverflow]: a page action keeps its place on every width.
  final List<Widget> addActions;

  /// Full-width content under the row, only while it is needed: the search
  /// suggestions while typing. Never a standing second row.
  final List<Widget> searchExtras;

  /// Groups of the filter popover. Empty hides the filter button.
  final List<WpFilterSection> filterSections;

  /// The filters in effect, as marks next to the search. Their number is the
  /// filter button's badge.
  final List<WpActiveFilter> activeFilters;

  /// Result count and view-bound actions (e.g. "Empty trash").
  final List<Widget> status;

  /// Select, sort and view controls, in this order.
  final List<Widget> tools;

  /// One button that stands in for [tools] on a narrow row.
  final Widget? toolsOverflow;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: '$screenId-toolbar',
      container: true,
      explicitChildNodes: true,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
          WpPageFrame.inset,
          WpSpacing.sm,
          WpPageFrame.inset,
          WpSpacing.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final inline =
                    toolsOverflow == null || width >= inlineToolsMinWidth;
                final trailingTools = [
                  if (inline) ...tools else ?toolsOverflow,
                ];
                const gap = SizedBox(width: WpSpacing.xs);
                // Every control stands at `WpLayout.controlHeight`, so the
                // row's default centring lands them on the same two edges.
                return Row(
                  children: [
                    Expanded(child: search),
                    if (activeFilters.isNotEmpty) ...[
                      gap,
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: width * marksMaxShare,
                        ),
                        child: Semantics(
                          identifier: '$screenId-filter-marks',
                          container: true,
                          explicitChildNodes: true,
                          child: WpFilterChipScroller(
                            children: [
                              for (final filter in activeFilters)
                                WpFilterMark(
                                  screenId: screenId,
                                  filter: filter,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    if (filterSections.isNotEmpty) ...[
                      gap,
                      WpFilterMenuButton(
                        screenId: screenId,
                        sections: filterSections,
                        activeCount: activeFilters.length,
                      ),
                    ],
                    if (status.isNotEmpty) ...[
                      gap,
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: width * statusMaxShare,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (var i = 0; i < status.length; i++) ...[
                              if (i > 0) gap,
                              Flexible(child: status[i]),
                            ],
                          ],
                        ),
                      ),
                    ],
                    for (final tool in trailingTools) ...[gap, tool],
                    for (var i = 0; i < addActions.length; i++) ...[
                      SizedBox(width: i == 0 ? WpSpacing.sm : WpSpacing.xs),
                      addActions[i],
                    ],
                    if (primaryAction != null) ...[
                      SizedBox(
                        width: addActions.isEmpty ? WpSpacing.sm : WpSpacing.xs,
                      ),
                      primaryAction!,
                    ],
                  ],
                );
              },
            ),
            ...searchExtras,
          ],
        ),
      ),
    );
  }
}
