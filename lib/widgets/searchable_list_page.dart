import '../core/search/search_ranker.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/config/command_shortcut.dart';
import '../core/l10n/generated/app_localizations.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import 'empty_state.dart';
import 'page_shell.dart' show WpPageFrame, WpPageShell;
import 'wp_collection_page.dart';
import 'wp_icon_button.dart';
import 'wp_collection_selection.dart';
import 'wp_collection_split.dart';
import 'wp_list_skeleton.dart';
import 'wp_search_field.dart';

export 'wp_collection_page.dart' show WpActiveFilter, WpFilterSection;

/// Shared scaffold for the searchable-list settings features (Replacements,
/// Snippets): a toolbar with search field and Add button above a searchable
/// list, with loading / error / empty / no-matches states.
///
/// Purely visual — data loading, dialogs, and deletion stay with the owning
/// page and are injected via callbacks. Rendering is pixel-identical to the
/// per-feature pages this was extracted from.
///
/// The frame is the page family's [WpCollectionPage], which itself sits in
/// [WpPageShell] (fixed mode, #197): subtitle, rows and skeleton share the
/// shell's side inset [WpPageFrame.inset] instead of a spacing of their own.
class WpSearchableListPage<T> extends StatefulWidget {
  const WpSearchableListPage({
    super.key,
    required this.asyncAll,
    required this.searchFields,
    required this.searchHint,
    required this.searchFieldLabel,
    required this.addLabel,
    required this.onAdd,
    required this.onRetry,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptyHint,
    required this.emptyActionLabel,
    this.emptyFooter,
    required this.itemBuilder,
    required this.onItemActivate,
    this.onItemDelete,
    this.onItemToggleSelect,
    this.onEscape,
    this.selectionBarBuilder,
    this.dimContent = false,
    this.listKey,
    this.menuActions = const [],
    this.menuKey,
    this.menuTooltip,
    this.identifierPrefix,
    this.header,
    this.notice,
    this.subtitle,
    this.skeletonRowHeight,
    this.sortControl,
    this.itemId,
    this.revealId,
    this.filterSections = const [],
    this.activeFilters = const [],
    this.status = const [],
    this.tools = const [],
    this.toolsOverflow,
    this.detailBuilder,
    this.selectedId,
  });

  /// The feature's full item list, as exposed by its Riverpod provider.
  final AsyncValue<List<T>> asyncAll;

  /// The texts of [item] the search ranks over, with their weights (e.g.
  /// title [SearchWeight.title], body [SearchWeight.body]).
  final List<SearchField> Function(T item) searchFields;

  /// Hint text of the toolbar search field.
  final String searchHint;

  /// Accessible name of the toolbar search field. Distinct from [searchHint]:
  /// a `hintText` publishes as a Semantics *hint*, not a *label* — see
  /// [WpSearchField]'s library docs — so a screen reader needs this to
  /// announce the field at all rather than reading it unnamed.
  final String searchFieldLabel;

  /// Label of the toolbar Add button.
  final String addLabel;

  /// Opens the feature's add dialog (toolbar button and empty-state CTA).
  final VoidCallback onAdd;

  /// Retries loading after an error (typically `ref.invalidate(provider)`).
  final VoidCallback onRetry;

  /// Icon, title, hint, and CTA label of the no-items-yet empty state.
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyHint;
  final String emptyActionLabel;

  /// Shown below the no-items-yet CTA (see [WpEmptyState.footer]).
  final Widget? emptyFooter;

  /// Builds one list tile. It used to receive the theme brightness as well,
  /// so tiles would not each re-derive it; with one theme left there is
  /// nothing to derive. [isCursor] is true for the one
  /// row the arrow keys currently point at — see the keyboard-cursor section
  /// of this state's docs; the tile must render it through
  /// `WpListTileSurface.isFocused` and `Semantics(selected:)`, never as a
  /// treatment of its own.
  final Widget Function(BuildContext context, T item, bool isCursor)
  itemBuilder;

  /// Opens [item] — what Enter does to the keyboard cursor's row, and what
  /// the tile's own `onTap` should do to the same row.
  ///
  /// Required rather than nullable: a searchable list whose rows cannot be
  /// opened from the keyboard is the defect this parameter exists to prevent,
  /// and there is no way for the shell to infer the action from
  /// [itemBuilder]'s closures.
  final void Function(T item) onItemActivate;

  /// Deletes [item] — what Delete/Backspace do to the keyboard cursor's row.
  ///
  /// Nullable because not every list is deletable, but nullable *with a
  /// condition*: a tile that reveals a delete action while it is the cursor
  /// row must pass this, or the row shows a trash icon that its own key does
  /// not reach. Both current call sites pass it.
  final void Function(T item)? onItemDelete;

  /// Space on the cursor row: toggles that row's membership in a selection.
  /// Null (the default) leaves Space alone.
  final void Function(T item)? onItemToggleSelect;

  /// Escape on the cursor row, asked before the cursor returns to the search
  /// field. Returns true when it consumed the key (a selection was left).
  final bool Function()? onEscape;

  /// Builds a bar that sits under the search toolbar while the page is in a
  /// selection mode; receives the rows the current search leaves visible so
  /// "select all" acts on what the user sees. Null result: no bar.
  final Widget? Function(BuildContext context, List<T> visible)?
  selectionBarBuilder;

  /// Dims the rows and the empty states (not the header or toolbar) to half
  /// opacity while the feature is switched off.
  final bool dimContent;

  /// Key of the list's scroll view, so tests and the keyboard layer can
  /// address it. Stable per screen.
  final ValueKey<String>? listKey;

  /// Secondary actions behind one overflow button in the toolbar. Empty means
  /// no button: the toolbar stays search plus Add.
  final List<WpListMenuAction> menuActions;

  /// Key and tooltip (accessible name) of that overflow button.
  final ValueKey<String>? menuKey;
  final String? menuTooltip;

  /// Prefix for the stable automation identifiers of the toolbar controls:
  /// `<prefix>-search` and `<prefix>-add`. Null leaves them unidentified.
  final String? identifierPrefix;

  /// Optional widget at the top of the list's scroll view, above the rows and
  /// shown in every load state (e.g. the Snippets page's picker-trigger field).
  /// It scrolls away with the rows. Include your own outer padding.
  final Widget? header;

  /// A page notice slot. Unlike [header] it stays fixed above the scrolling
  /// list, so a failure is not scrolled out of sight (#599).
  final Widget? notice;

  /// Height of one loading-skeleton placeholder bar, when this page's rows
  /// are taller than the single-line default. See
  /// [_searchableListSkeletonRowHeight].
  final double? skeletonRowHeight;

  /// Optional sort button in the toolbar, between the search field and Add.
  final Widget? sortControl;

  /// Stable identity of [item]. Rows are keyed by it, so a row keeps its state
  /// (hover, focus) when a re-sort moves it, and [revealId] finds it. Null
  /// keys rows by position and disables the reveal.
  final Object Function(T item)? itemId;

  /// Identity of an item that was just created. When it changes, the list
  /// scrolls it into view, if it is among the visible items: an active search
  /// that does not match it is left as it is.
  final Object? revealId;

  /// Groups of the toolbar's filter popover (see [WpCollectionToolbar]).
  final List<WpFilterSection> filterSections;

  /// The filters in effect, as removable marks next to the search.
  final List<WpActiveFilter> activeFilters;

  /// View-bound status and actions (e.g. "Empty trash"), after the filter.
  final List<Widget> status;

  /// Select, sort and view controls, end of row two. [sortControl] and the
  /// [menuActions] button are appended to them.
  final List<Widget> tools;

  /// One button that stands in for [tools] on a narrow toolbar.
  final Widget? toolsOverflow;

  /// Builds the detail pane for the open item. Non-null turns the body into
  /// the family's list/detail split (`WpCollectionSplit`); needs [itemId].
  final Widget Function(BuildContext context, T item)? detailBuilder;

  /// Identity (as [itemId] returns it) of the item whose detail is open.
  final Object? selectedId;

  /// One-line explanation of what this page is for, rendered directly under
  /// the page H1 and above everything else (ticket 03, point 4).
  ///
  /// Persistent on purpose. The same sentence already existed as the empty
  /// state's `hint`, which meant the page explained itself only to users who
  /// had nothing in it yet — the moment a first entry appeared, the answer to
  /// "what does this screen actually do" disappeared for good. Callers pass
  /// their existing `emptyHint` string, so this costs no new translation and
  /// the two states cannot drift apart.
  ///
  /// Deliberately outside the `AsyncValue.when` below: an explanation that
  /// vanishes while the list is loading or errored is exactly the sort of
  /// chrome flicker `WpListSkeleton` was introduced to stop.
  final String? subtitle;

  @override
  State<WpSearchableListPage<T>> createState() =>
      _WpSearchableListPageState<T>();
}

/// Default placeholder-bar height of the loading skeleton — the height of a
/// [WpSearchableListPage] row whose content is a single line.
///
/// The two features used to share one value because they measured the same:
/// 70 dp each, "identical anatomy — `md`/`sm` padding around a title line plus
/// a one-line preview". Ticket 03 ended that. Re-measured at full list width
/// afterwards, a Replacements row is 71 dp (the 1 dp is the shared envelope's
/// border going from 1.0 to 1.5) and a Snippets row is 87, because its body
/// preview now takes two lines so a row is identifiable without opening it.
///
/// Rather than average the two into a placeholder that reflows on both pages,
/// the value stayed the caller's to state: this is the default, and Snippets
/// passes [WpSearchableListPage.skeletonRowHeight] instead. Both numbers are
/// measurements, so they move when the rows do — `wp_list_skeleton_test.dart`
/// is where that gets caught.
const _searchableListSkeletonRowHeight = 71.0;

// The keyboard cursor (search query, arrows, J/K, Enter, Delete, Escape) is
// the shared [WpCollectionSelection]; this shell only scrolls its row into
// view.

class _WpSearchableListPageState<T> extends State<WpSearchableListPage<T>> {
  /// Query, cursor and bare keys (#1498). The debug label keeps the focus
  /// nodes recognisable in focus dumps and tests.
  final _selection = WpCollectionSelection<T>(
    debugLabel: 'WpSearchableListPage',
  );

  /// One key per row *position*, so [Scrollable.ensureVisible] has a context
  /// to reveal.
  ///
  /// Every row is wrapped, not just the cursor's. Wrapping only the cursor
  /// was tried first and is a trap: moving the wrapper off a row changes the
  /// widget at that slot from `KeyedSubtree` to the tile itself, which no
  /// element can update into — so the row was torn down and rebuilt on every
  /// cursor step, taking its focus node with it. That is invisible until
  /// something actually holds focus in there: Tab out of the cursor row moved
  /// focus into the row, the rebuild destroyed the node it had just landed
  /// on, and focus fell back to the list — a keyboard trap produced entirely
  /// by a scrolling helper. Keeping the wrapper on every row keeps the
  /// structure constant.
  final _rowKeys = <Object, GlobalKey>{};

  /// Keyed by [WpSearchableListPage.itemId] when given, else by position.
  Object _rowIdentity(int index, List<T> visible) {
    final id = widget.itemId;
    return id == null ? index : id(visible[index]);
  }

  GlobalKey _rowKey(Object identity) => _rowKeys.putIfAbsent(
    identity,
    () => GlobalKey(debugLabel: 'WpSearchableListPage row $identity'),
  );

  /// Owned here so a reveal can jump the list before the row is built.
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _selection.addListener(_onSelectionChanged);
  }

  void _onSelectionChanged() => setState(() {});

  @override
  void didUpdateWidget(covariant WpSearchableListPage<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final revealId = widget.revealId;
    if (revealId != null && revealId != oldWidget.revealId) {
      // After the frame that shows the new item: it is part of `asyncAll` by now.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _revealItem(revealId),
      );
    }
  }

  /// Scrolls the item with [id] into view. A row that is not built yet is
  /// reached by a jump to its estimated offset first, which builds it, and
  /// then the same reveal runs again. A few attempts, then it gives up.
  void _revealItem(Object id, {int attempt = 0}) {
    if (!mounted || widget.itemId == null) return;
    final visible = _visibleNow;
    final index = visible.indexWhere((item) => widget.itemId!(item) == id);
    if (index < 0) return;
    final rowContext = _rowKeys[id]?.currentContext;
    if (rowContext != null) {
      Scrollable.ensureVisible(
        rowContext,
        alignment: 0.5,
        duration: WpMotion.durationFor(context, WpMotion.normal),
        curve: WpMotion.defaultCurve,
      );
      return;
    }
    if (attempt >= 3 || !_scrollController.hasClients) return;
    final rowExtent =
        (widget.skeletonRowHeight ?? _searchableListSkeletonRowHeight) +
        WpSpacing.xs;
    final position = _scrollController.position;
    _scrollController.jumpTo(
      (index * rowExtent).clamp(0.0, position.maxScrollExtent),
    );
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _revealItem(id, attempt: attempt + 1),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _selection
      ..removeListener(_onSelectionChanged)
      ..dispose();
    super.dispose();
  }

  List<T> _filtered(List<T> all) => _selection.filter(all, widget.searchFields);

  /// The filtered list as the *key handler* sees it. `build` derives the same
  /// list from the same two inputs; deriving it here too keeps the handler
  /// correct without a copy of the list in state that could go stale between
  /// a provider emission and the next frame.
  List<T> get _visibleNow => _filtered(widget.asyncAll.value ?? const []);

  /// Scrolls just enough to bring the cursor row inside the viewport, in the
  /// direction of travel — the policy Flutter's own focus traversal uses, and
  /// the reason arrowing through a long list doesn't re-centre on every step.
  ///
  /// Null-safe on purpose: a row far outside the viewport's cache extent has
  /// no context to reveal. The cursor only ever moves one row at a time, so
  /// the neighbour is always built and the case is the harmless one.
  void _revealCursor(int delta) {
    if (!mounted) return;
    final visible = _visibleNow;
    final cursor = _selection.cursorIndex;
    if (cursor < 0 || cursor >= visible.length) return;
    final rowContext = _rowKeys[_rowIdentity(cursor, visible)]?.currentContext;
    if (rowContext == null) return;
    Scrollable.ensureVisible(
      rowContext,
      alignment: 0,
      alignmentPolicy: delta > 0
          ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
          : ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      duration: WpMotion.durationFor(context, WpMotion.fast),
      curve: WpMotion.defaultCurve,
    );
  }

  /// `<identifierPrefix>-<suffix>`, or null when no prefix was given.
  String? _id(String suffix) => widget.identifierPrefix == null
      ? null
      : '${widget.identifierPrefix}-$suffix';

  KeyEventResult _handlePageKeyEvent(FocusNode node, KeyEvent event) =>
      _selection.handleKey(
        event,
        visible: _visibleNow,
        onActivate: widget.onItemActivate,
        onDelete: widget.onItemDelete,
        onToggleSelect: widget.onItemToggleSelect,
        onEscape: widget.onEscape,
        onReveal: _revealCursor,
      );

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    // Sits between the page H1 (drawn by `_PageHeader` in app.dart, outside
    // this widget) and the list, continuing the H1's `xl` gutter. It wraps
    // to as many lines as it needs: a one-line cap with an ellipsis cut the
    // sentence mid-thought at 800 px and text scale 1.0 (UX-014).
    final subtitleLine = widget.subtitle == null
        ? null
        : Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              WpPageFrame.inset,
              0,
              WpPageFrame.inset,
              WpSpacing.xs,
            ),
            // The `Align` is load-bearing, not decoration: this Padding is a
            // child of a `Column` whose cross-axis alignment is the default
            // `center`, so a bare Text shrink-wraps its own string and the
            // sentence lands centred under a left-aligned H1. `Align` expands
            // to the bounded width it is offered (RenderPositionedBox) and
            // then places the text at the start edge — directional, so RTL
            // locales get the mirror.
            // `container: true` so this sentence is a node of its own instead
            // of being absorbed by whatever sits next to it. Without it the
            // line folded into the page-level focus node that the following
            // widget's own announcement is read from — on Replacements that
            // meant the master switch was announced as "Add replacements to
            // auto-replace words while recording. … Enable replacements",
            // i.e. a page-level explanation became part of a control's name.
            // Exactly the defect `replacements_page_test.dart` already guards
            // the switch against.
            child: Semantics(
              container: true,
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  widget.subtitle!,
                  style: TextStyle(
                    fontSize: WpTypography.small,
                    color: WpColors.textMuted,
                  ),
                ),
              ),
            ),
          );

    // Explanation, banners and a feature's own header card are the first
    // sliver of the same scroll view as the rows, so they scroll away with
    // the list instead of taking the viewport from it (ticket). Only the
    // toolbar stays fixed above the scroll view.
    final headerChildren = <Widget>[?subtitleLine, ?widget.header];
    final headerSliver = SliverToBoxAdapter(
      child: headerChildren.isEmpty
          ? const SizedBox.shrink()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: headerChildren,
            ),
    );

    final content = widget.asyncAll
        .when<({Widget? selectionBar, T? open, List<Widget> slivers})>(
          // Same list-shaped placeholder History and Notes use. A centred
          // spinner used to sit here, which made these two the only list
          // surfaces in the app whose loading state neither reserved the
          // rows' space nor matched its siblings — the list visibly re-flowed
          // the moment data arrived.
          loading: () => (
            selectionBar: null,
            open: null,
            slivers: [
              headerSliver,
              // The skeleton is itself a list, so it is a scroll body: a box
              // child would ask the viewport for intrinsic sizes it cannot give.
              SliverFillRemaining(
                child: WpListSkeleton(
                  rowHeight:
                      widget.skeletonRowHeight ??
                      _searchableListSkeletonRowHeight,
                  // The real rows below sit on the `xl` gutter, not the
                  // skeleton's history/notes default — pass it so the bars
                  // land on their edge.
                  padding: const EdgeInsets.symmetric(
                    horizontal: WpPageFrame.inset,
                    vertical: WpSpacing.xs,
                  ),
                ),
              ),
            ],
          ),
          error: (e, _) => (
            selectionBar: null,
            open: null,
            slivers: [
              headerSliver,
              SliverFillRemaining(
                // WpEmptyState sizes itself to the pane (no intrinsics).
                hasScrollBody: true,
                child: WpEmptyState(
                  icon: LucideIcons.triangleAlert,
                  title: l10n.errorGeneric,
                  actionLabel: l10n.actionRetry,
                  actionTestId: 'list-retry',
                  onAction: widget.onRetry,
                ),
              ),
            ],
          ),
          data: (all) {
            final visible = _filtered(all);
            // Derived, never stored: an item can be deleted out from under the
            // cursor between two frames, and the list can shrink under a new
            // query before `onChanged`'s reset has been rebuilt.
            final cursor = _selection.cursorIn(visible);
            final Widget rows;
            if (all.isEmpty) {
              rows = SliverFillRemaining(
                // WpEmptyState sizes itself to the pane (no intrinsics).
                hasScrollBody: true,
                child: WpEmptyState(
                  icon: widget.emptyIcon,
                  title: widget.emptyTitle,
                  // The page subtitle may already say the same thing
                  // (snippets); saying it twice pushes the action down.
                  hint: widget.emptyHint == widget.subtitle
                      ? null
                      : widget.emptyHint,
                  actionLabel: widget.emptyActionLabel,
                  actionTestId: 'list-empty-add',
                  onAction: widget.onAdd,
                  footer: widget.emptyFooter,
                ),
              );
            } else if (visible.isEmpty) {
              rows = SliverFillRemaining(
                // WpEmptyState sizes itself to the pane (no intrinsics).
                hasScrollBody: true,
                child: WpEmptyState.searchNoMatches(
                  query: _selection.query,
                  testId: _id('search-clear') ?? 'list-search-clear',
                  onClear: _selection.clearSearch,
                ),
              );
            } else {
              rows = SliverPadding(
                padding: const EdgeInsets.symmetric(
                  horizontal: WpPageFrame.inset,
                  vertical: WpSpacing.xs,
                ),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => KeyedSubtree(
                      key: _rowKey(_rowIdentity(index, visible)),
                      child: Padding(
                        padding: EdgeInsets.only(
                          bottom: index < visible.length - 1 ? WpSpacing.xs : 0,
                        ),
                        child: widget.itemBuilder(
                          context,
                          visible[index],
                          index == cursor,
                        ),
                      ),
                    ),
                    childCount: visible.length,
                  ),
                ),
              );
            }
            final selectedId = widget.selectedId;
            final idOf = widget.itemId;
            T? open;
            if (selectedId != null && idOf != null) {
              for (final item in all) {
                if (idOf(item) == selectedId) {
                  open = item;
                  break;
                }
              }
            }
            return (
              selectionBar: widget.selectionBarBuilder?.call(context, visible),
              open: open,
              slivers: [
                headerSliver,
                SliverAnimatedOpacity(
                  // Dimmed while the feature is switched off: the rows stay
                  // readable as shortcuts but read as inactive.
                  opacity: widget.dimContent ? 0.5 : 1.0,
                  duration: WpMotion.durationFor(context, WpMotion.normal),
                  sliver: rows,
                ),
              ],
            );
          },
        );

    final list = Focus(
      // The list's focus anchor sits *inside* the content wrapper so it stays
      // mounted across every data state — losing the node while a dialog is
      // open would drop the cursor the dialog was opened from.
      // `skipTraversal` keeps it out of the Tab order: Tab from here continues
      // into the rows themselves, exactly as it did before the cursor existed.
      focusNode: _selection.listFocusNode,
      skipTraversal: true,
      child: CustomScrollView(
        key: widget.listKey,
        controller: _scrollController,
        slivers: content.slivers,
      ),
    );
    final detailBuilder = widget.detailBuilder;
    final idOf = widget.itemId;
    final body = detailBuilder == null || idOf == null
        ? list
        : WpCollectionSplit<T>(
            selectedItem: content.open,
            idOf: (item) => idOf(item).toString(),
            listBuilder: (_, _) => list,
            detailBuilder: detailBuilder,
          );

    // Ctrl+F / Cmd+F (focus the search) is bound once by the page-family
    // frame, `WpCollectionPage`, which this shell renders through.
    //
    // Ctrl+N / Cmd+N adds an item: Notes had it, its two sibling list screens
    // did not, so "create without reaching for the mouse" was a skill that
    // only worked on one of the three. No text-field guard, deliberately —
    // Ctrl/Cmd+N is not a text-editing binding on any of the three platforms
    // (Flutter binds Ctrl+N to "line down" only in its macOS Emacs set, and
    // there we send Cmd+N), so consuming it while the search field has focus
    // costs nothing and firing it there is what every desktop app does.
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        commandActivator(LogicalKeyboardKey.keyN): widget.onAdd,
      },
      // `skipTraversal` so this wrapper never becomes a Tab stop of its own;
      // it exists only to give the shortcut a focused descendant to bubble
      // from — and, since it is the one node that is an ancestor of both the
      // search field and the list, to carry the arrow-cursor's bare keys (see
      // `_handlePageKeyEvent`).
      child: Focus(
        autofocus: true,
        skipTraversal: true,
        onKeyEvent: _handlePageKeyEvent,
        child: WpCollectionPage(
          screenId: _screenId,
          searchFocusNode: _selection.searchFocusNode,
          selectionBar: content.selectionBar,
          notices: [?widget.notice],
          toolbar: _toolbar(context),
          body: body,
        ),
      ),
    );
  }

  /// Landmark prefix of the page-family frame.
  String get _screenId => widget.identifierPrefix ?? 'list';

  /// The page-family toolbar, one row: search, filter marks and popover,
  /// status, tools and Add. A legacy [WpSearchableListPage.sortControl]
  /// and the [WpSearchableListPage.menuActions] button join the tools, so no
  /// control keeps a place of its own.
  Widget _toolbar(BuildContext context) {
    return WpCollectionToolbar(
      screenId: _screenId,
      search: WpSearchField(
        testId: _id('search'),
        controller: _selection.searchController,
        focusNode: _selection.searchFocusNode,
        hintText: widget.searchHint,
        variant: WpSearchFieldVariant.outlined,
        // Every keystroke re-filters, so the index the cursor held points at
        // a different item than the one the user was looking at. Dropping it
        // is the same reset the settings search dropdown does on every text
        // change.
        onChanged: _selection.setQuery,
        semanticsLabel: widget.searchFieldLabel,
      ),
      // An icon button of the field's height (WpLayout.controlHeight, UX-131).
      // The label is the tooltip and the accessible name.
      primaryAction: Semantics(
        identifier: _id('add'),
        child: WpIconButton(
          icon: LucideIcons.plus,
          tooltip: widget.addLabel,
          onPressed: widget.onAdd,
        ),
      ),
      filterSections: widget.filterSections,
      activeFilters: widget.activeFilters,
      status: widget.status,
      tools: [
        ...widget.tools,
        ?widget.sortControl,
        if (widget.menuActions.isNotEmpty)
          Builder(
            builder: (buttonContext) => Semantics(
              identifier: widget.menuKey?.value,
              child: WpIconButton(
                key: widget.menuKey,
                icon: LucideIcons.ellipsis,
                tooltip: widget.menuTooltip ?? '',
                onPressed: () => _openMenu(buttonContext),
              ),
            ),
          ),
      ],
      toolsOverflow: widget.toolsOverflow,
    );
  }

  /// Opens the overflow menu under its button.
  void _openMenu(BuildContext buttonContext) =>
      showWpListMenu(buttonContext, widget.menuActions);
}

/// Opens a list's action menu under the button [buttonContext] belongs to.
/// Items are plain menu rows, so a secondary action costs no space on the page
/// until it is asked for. Shared with the toolbar's sort button.
Future<void> showWpListMenu(
  BuildContext buttonContext,
  List<WpListMenuAction> actions,
) async {
  final overlay =
      Overlay.of(buttonContext).context.findRenderObject()! as RenderBox;
  final button = buttonContext.findRenderObject()! as RenderBox;
  final anchor = Rect.fromPoints(
    button.localToGlobal(Offset.zero, ancestor: overlay),
    button.localToGlobal(
      button.size.bottomRight(Offset.zero),
      ancestor: overlay,
    ),
  );
  final chosen = await showMenu<WpListMenuAction>(
    context: buttonContext,
    popUpAnimationStyle: MediaQuery.disableAnimationsOf(buttonContext)
        ? AnimationStyle.noAnimation
        : null,
    position: RelativeRect.fromRect(anchor, Offset.zero & overlay.size),
    shape: RoundedRectangleBorder(borderRadius: WpRadius.borderSm),
    items: [
      for (final action in actions) ...[
        if (action.dividerBefore) const PopupMenuDivider(),
        PopupMenuItem<WpListMenuAction>(
          key: action.itemKey,
          value: action,
          enabled: action.enabled,
          child: _ListMenuRow(action: action),
        ),
      ],
    ],
  );
  chosen?.onSelected();
}

/// One entry of a searchable list's overflow menu.
///
/// [checked] renders a state mark for toggle-like entries; null means the
/// entry is a plain action. [hint] is an optional second line explaining what
/// the action does before the user commits to it.
class WpListMenuAction {
  const WpListMenuAction({
    required this.itemKey,
    required this.label,
    required this.icon,
    required this.onSelected,
    this.hint,
    this.checked,
    this.enabled = true,
    this.dividerBefore = false,
  });

  final ValueKey<String> itemKey;
  final String label;
  final String? hint;
  final IconData icon;
  final bool? checked;
  final bool enabled;
  final VoidCallback onSelected;

  /// Draws a divider above this entry, to start a new group (view, sort,
  /// selection in the history's tools menu).
  final bool dividerBefore;
}

class _ListMenuRow extends StatelessWidget {
  const _ListMenuRow({required this.action});

  final WpListMenuAction action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hint = action.hint;
    final checked = action.checked;
    // A checkable row announces its on/off state; the check icon is visual only.
    // One node per row: the label is the action, the hint is its state or
    // detail. Excluding the child text keeps the visible hint from being
    // merged into the label.
    return Semantics(
      identifier: action.itemKey.value,
      label: action.label,
      hint: hint,
      toggled: checked,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 220, maxWidth: 340),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(action.icon, size: WpIconSize.sm, color: WpColors.textMuted),
            const SizedBox(width: WpSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(action.label, style: theme.textTheme.bodyMedium),
                  if (hint != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        hint,
                        style: TextStyle(
                          fontSize: WpTypography.small,
                          color: WpColors.textMuted,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (checked != null) ...[
              const SizedBox(width: WpSpacing.sm),
              SizedBox(
                width: WpIconSize.sm,
                child: checked
                    ? Icon(
                        LucideIcons.check,
                        size: WpIconSize.sm,
                        color: theme.colorScheme.primary,
                      )
                    : null,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
