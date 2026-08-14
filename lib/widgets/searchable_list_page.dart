import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/l10n/generated/app_localizations.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import 'dialog.dart';
import 'empty_state.dart';
import 'page_shell.dart';
import 'wp_button.dart';
import 'wp_list_skeleton.dart';
import 'wp_search_field.dart';

/// Shared scaffold for the searchable-list settings features (Replacements,
/// Snippets): a toolbar with search field and Add button above a searchable
/// list, with loading / error / empty / no-matches states.
///
/// Purely visual — data loading, dialogs, and deletion stay with the owning
/// page and are injected via callbacks. Rendering is pixel-identical to the
/// per-feature pages this was extracted from.
class WpSearchableListPage<T> extends StatefulWidget {
  const WpSearchableListPage({
    super.key,
    required this.asyncAll,
    required this.searchMatches,
    required this.searchHint,
    required this.searchFieldLabel,
    required this.addLabel,
    required this.onAdd,
    required this.onRetry,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptyHint,
    required this.emptyActionLabel,
    required this.noMatchesTitle,
    required this.noMatchesHint,
    required this.itemBuilder,
    required this.onItemActivate,
    this.onItemDelete,
    this.contentWrapper,
    this.header,
    this.subtitle,
    this.skeletonRowHeight,
  });

  /// The feature's full item list, as exposed by its Riverpod provider.
  final AsyncValue<List<T>> asyncAll;

  /// Whether [item] matches the search query. Called only for non-empty
  /// queries.
  ///
  /// Uses a precompiled, case-insensitive `RegExp` instead of repeatedly
  /// calling `String.toLowerCase()` on every iteration to avoid excessive
  /// memory allocation overhead during tight loops (e.g., when the list is large).
  final bool Function(T item, RegExp query) searchMatches;

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

  /// Title and hint of the search-found-nothing empty state.
  final String noMatchesTitle;
  final String noMatchesHint;

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

  /// Optional wrapper around the list / empty-state area (e.g. dimming via
  /// `AnimatedOpacity` while the feature is disabled).
  final Widget Function(BuildContext context, Widget child)? contentWrapper;

  /// Optional widget above the toolbar, shown in every load state (e.g. the
  /// Snippets page's picker-trigger field). Include your own outer padding.
  final Widget? header;

  /// Height of one loading-skeleton placeholder bar, when this page's rows
  /// are taller than the single-line default. See
  /// [_searchableListSkeletonRowHeight].
  final double? skeletonRowHeight;

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

/// Height the page keeps for its own body when an oversized header would
/// otherwise take everything: the search toolbar plus roughly one row, at
/// text scale 1.0. Scaled with the system font size at the point of use —
/// see [_WpSearchableListPageState._cappedHeader].
const _searchableListBodyReserve = 130.0;

// ---------------------------------------------------------------------------
// The keyboard cursor
//
// Replacements and Snippets used to be reachable by Tab and nothing else: at
// 40 entries, "open the third one" cost 40 keystrokes, on the two screens
// whose whole point is a list you maintain. Verlauf and Notizen have had an
// arrow cursor since they existed, so this was the one keyboard skill that
// stopped working halfway across the app.
//
// The model is *rebuilt* from Verlauf/Notizen (`CONTEXT.md` §5.9), not
// imported: one page-level index into the **filtered** list, rendered by the
// rows and moved by the page. What differs, and why:
//
//   * **Entry point.** In Verlauf/Notizen every bare key is dropped while a
//     text field has focus. Here the search field *is* the way in — it holds
//     focus the moment the page opens — so ArrowDown is deliberately not
//     guarded: it takes the caret out of the field and puts the cursor on the
//     first row. Escape is the way back. Everything else (Enter, Delete,
//     Backspace) only fires while the cursor is live, i.e. while focus sits
//     on the list node and no text field can be typing.
//   * **Scrolling.** The reference model does not scroll its cursor into
//     view; a panel list is short enough to get away with it. A full-width
//     page list is not, and a cursor that walks off the bottom edge answers
//     the 40-entry problem with a 40-entry problem, so this one scrolls —
//     minimally, in the direction of travel, via a single [GlobalKey] on
//     whichever row is currently the cursor.
//
// One highlight at a time is structural rather than remembered: the index is
// only rendered while [_listFocusNode] holds *primary* focus. Tab moves focus
// into a row itself, the list node stops being primary, and the cursor stops
// painting — so the row's own focus treatment is never in competition with
// it. The index survives, which is what makes Enter → dialog → close return
// to row 20 instead of to the top.
// ---------------------------------------------------------------------------

class _WpSearchableListPageState<T> extends State<WpSearchableListPage<T>> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode(debugLabel: 'WpSearchableListPage search');

  /// Holds real focus while the arrow cursor is live. `skipTraversal` where
  /// it is mounted: it is a target of [FocusNode.requestFocus], never a Tab
  /// stop, so the row-by-row Tab order it sits in front of is unchanged.
  final _listFocusNode = FocusNode(debugLabel: 'WpSearchableListPage list');

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
  final _rowKeys = <int, GlobalKey>{};

  GlobalKey _rowKey(int index) => _rowKeys.putIfAbsent(
    index,
    () => GlobalKey(debugLabel: 'WpSearchableListPage row $index'),
  );

  String _searchQuery = '';

  /// Index into the *filtered* list, or -1 for "no cursor". Rendered only
  /// while [_listFocusNode] has primary focus — see the section comment.
  int _cursorIndex = -1;
  bool _listHasPrimaryFocus = false;

  @override
  void initState() {
    super.initState();
    _listFocusNode.addListener(_onListFocusChanged);
  }

  @override
  void dispose() {
    _listFocusNode.removeListener(_onListFocusChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _listFocusNode.dispose();
    super.dispose();
  }

  void _onListFocusChanged() {
    if (_listHasPrimaryFocus == _listFocusNode.hasPrimaryFocus) return;
    setState(() => _listHasPrimaryFocus = _listFocusNode.hasPrimaryFocus);
  }

  /// Resets the search from outside the field (the no-matches empty state).
  /// Mirrors what the field's own clear button does — [TextEditingController]
  /// fires no `onChanged`, so the query has to be reset alongside the text.
  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _cursorIndex = -1;
    });
  }

  List<T> _filtered(List<T> all) {
    if (_searchQuery.isEmpty) return all;
    // Bolt: Use precompiled RegExp with caseSensitive: false instead of
    // repeatedly calling toLowerCase() to prevent excessive memory allocation
    // overhead in the tight loop below.
    final q = RegExp(RegExp.escape(_searchQuery), caseSensitive: false);
    return all.where((item) => widget.searchMatches(item, q)).toList();
  }

  /// The filtered list as the *key handler* sees it. `build` derives the same
  /// list from the same two inputs; deriving it here too keeps the handler
  /// correct without a copy of the list in state that could go stale between
  /// a provider emission and the next frame.
  List<T> get _visibleNow => _filtered(widget.asyncAll.value ?? const []);

  /// The item under the cursor, or null when the cursor is not live — which
  /// is also the guard that keeps Enter/Delete from firing while the caret is
  /// in the search field.
  T? _cursorItem(List<T> visible) {
    if (!_listHasPrimaryFocus) return null;
    if (_cursorIndex < 0 || _cursorIndex >= visible.length) return null;
    return visible[_cursorIndex];
  }

  /// Moves the cursor by [delta], or places it when it is not live yet:
  /// ArrowDown enters at the top, ArrowUp at the bottom. Clamps at both ends
  /// rather than wrapping — the same choice Verlauf and Notizen made, so the
  /// list's first and last row stay a place you can arrive at and stop.
  KeyEventResult _moveCursor(int delta, List<T> visible) {
    if (visible.isEmpty) return KeyEventResult.ignored;
    final live = _listHasPrimaryFocus && _cursorIndex >= 0;
    final next = live
        ? (_cursorIndex + delta).clamp(0, visible.length - 1)
        : (delta > 0 ? 0 : visible.length - 1);
    setState(() => _cursorIndex = next);
    // Before the frame, so the row is already the cursor when it is revealed.
    _listFocusNode.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealCursor(delta));
    return KeyEventResult.handled;
  }

  /// Scrolls just enough to bring the cursor row inside the viewport, in the
  /// direction of travel — the policy Flutter's own focus traversal uses, and
  /// the reason arrowing through a long list doesn't re-centre on every step.
  ///
  /// Null-safe on purpose: a row far outside the viewport's cache extent has
  /// no context to reveal. The cursor only ever moves one row at a time, so
  /// the neighbour is always built and the case is the harmless one.
  void _revealCursor(int delta) {
    if (!mounted) return;
    final rowContext = _rowKeys[_cursorIndex]?.currentContext;
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

  /// Escape: hand the caret back to the search field and drop the cursor.
  /// The one direction Tab cannot express — from the middle of a list back to
  /// the control that filtered it.
  void _returnToSearch() {
    setState(() => _cursorIndex = -1);
    _searchFocusNode.requestFocus();
  }

  /// Bare-key handler for the whole page, mounted on the page's existing
  /// [Focus] wrapper because that node is an ancestor of both the search
  /// field and the list — so the keys arrive wherever focus happens to sit,
  /// including on a page that has just opened and where neither the field nor
  /// the list is focused yet.
  ///
  /// Runs *below* the app-level [DefaultTextEditingShortcuts], which is why
  /// ArrowUp/ArrowDown reach it at all while the search field has focus. The
  /// price is that those two keys no longer jump the caret to the start/end
  /// of the query — a single-line field, where Home/End say the same thing.
  KeyEventResult _handlePageKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final visible = _visibleNow;

    if (key == LogicalKeyboardKey.arrowDown) return _moveCursor(1, visible);
    if (key == LogicalKeyboardKey.arrowUp) return _moveCursor(-1, visible);

    // Everything below acts on the cursor's row, so it is inert unless the
    // cursor is live — which also means no text field can have focus.
    final item = _cursorItem(visible);
    if (item == null) return KeyEventResult.ignored;

    if (key == LogicalKeyboardKey.enter) {
      widget.onItemActivate(item);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      // Same keys, same reasoning as the per-row binding these two pages
      // already carry for Tab focus — the cursor row simply has no focused
      // descendant for that binding to fire from.
      widget.onItemDelete?.call(item);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      _returnToSearch();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    // Sits between the page H1 (drawn by `_PageHeader` in app.dart, outside
    // this widget) and the toolbar, continuing the H1's `xl` gutter. Capped
    // at one line: this is a subtitle, not body copy — a sentence that needs
    // two lines belongs in the empty state, which has room for it.
    final subtitleLine = widget.subtitle == null
        ? null
        : Padding(
            padding: const EdgeInsets.fromLTRB(
              WpSpacing.xl,
              0,
              WpSpacing.xl,
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: WpTypography.small,
                    color: WpColors.textMuted,
                  ),
                ),
              ),
            ),
          );

    final body = widget.asyncAll.when(
      // Same list-shaped placeholder History and Notes use. A centred spinner
      // used to sit here, which made these two the only list surfaces in the
      // app whose loading state neither reserved the rows' space nor matched
      // its siblings — the list visibly re-flowed the moment data arrived.
      loading: () => WpListSkeleton(
        rowHeight: widget.skeletonRowHeight ?? _searchableListSkeletonRowHeight,
        // The real rows below sit on the `xl` gutter, not the skeleton's
        // history/notes default — pass it so the bars land on their edge.
        padding: const EdgeInsets.symmetric(
          horizontal: WpSpacing.xl,
          vertical: WpSpacing.xs,
        ),
      ),
      error: (e, _) => WpEmptyState(
        icon: LucideIcons.triangleAlert,
        title: l10n.errorGeneric,
        actionLabel: l10n.actionRetry,
        onAction: widget.onRetry,
      ),
      data: (all) {
        final visible = _filtered(all);
        // Derived, never stored: an item can be deleted out from under the
        // cursor between two frames, and the list can shrink under a new
        // query before `onChanged`'s reset has been rebuilt.
        final cursor =
            (_listHasPrimaryFocus &&
                _cursorIndex >= 0 &&
                _cursorIndex < visible.length)
            ? _cursorIndex
            : -1;
        final content = all.isEmpty
            ? WpEmptyState(
                icon: widget.emptyIcon,
                title: widget.emptyTitle,
                hint: widget.emptyHint,
                actionLabel: widget.emptyActionLabel,
                onAction: widget.onAdd,
              )
            : visible.isEmpty
            ? WpEmptyState(
                icon: LucideIcons.searchX,
                title: widget.noMatchesTitle,
                hint: widget.noMatchesHint,
                // Per the WpEmptyState rule the search-empty state offers its
                // main action: get out of the search. Verlauf and Notizen say
                // the same thing with their own keys, whose wording is
                // byte-identical to the generic one in every locale — so this
                // reuses the generic key instead of minting a fourth string.
                actionLabel: l10n.actionClearSearch,
                onAction: _clearSearch,
              )
            : ListView.separated(
                padding: const EdgeInsets.symmetric(
                  horizontal: WpSpacing.xl,
                  vertical: WpSpacing.xs,
                ),
                itemCount: visible.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: WpSpacing.xs),
                itemBuilder: (context, index) => KeyedSubtree(
                  key: _rowKey(index),
                  child: widget.itemBuilder(
                    context,
                    visible[index],
                    index == cursor,
                  ),
                ),
              );
        return Column(
          children: [
            // Toolbar
            Padding(
              padding: const EdgeInsets.fromLTRB(
                WpSpacing.xl,
                WpSpacing.sm,
                WpSpacing.xl,
                WpSpacing.sm,
              ),
              child: Row(
                children: [
                  // Search
                  Expanded(
                    child: WpSearchField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      hintText: widget.searchHint,
                      variant: WpSearchFieldVariant.outlined,
                      // Every keystroke re-filters, so the index the cursor
                      // held points at a different item than the one the user
                      // was looking at. Dropping it is the same reset the
                      // settings search dropdown does on every text change.
                      onChanged: (v) => setState(() {
                        _searchQuery = v;
                        _cursorIndex = -1;
                      }),
                      semanticsLabel: widget.searchFieldLabel,
                    ),
                  ),
                  const SizedBox(width: WpSpacing.sm),
                  // Add button
                  WpButton(
                    label: widget.addLabel,
                    variant: WpButtonVariant.primary,
                    icon: LucideIcons.plus,
                    onPressed: widget.onAdd,
                  ),
                ],
              ),
            ),
            Expanded(
              // The list's focus anchor sits *inside* the content wrapper so
              // it stays mounted across every data state — losing the node
              // while a dialog is open would drop the cursor the dialog was
              // opened from. `skipTraversal` keeps it out of the Tab order:
              // Tab from here continues into the rows themselves, exactly as
              // it did before the cursor existed.
              child: Focus(
                focusNode: _listFocusNode,
                skipTraversal: true,
                child: widget.contentWrapper?.call(context, content) ?? content,
              ),
            ),
          ],
        );
      },
    );

    // Ctrl+F / Cmd+F focuses the search field — the one shortcut History,
    // Notes and Settings all bind. Snippets and Replacements were the only
    // searchable surfaces without it, so the muscle memory broke on exactly
    // two of five screens. Binding it on the shared shell fixes both at once.
    //
    // Ctrl+N / Cmd+N adds an item, for the same reason: Notes had it, its two
    // sibling list screens did not, so "create without reaching for the
    // mouse" was a skill that only worked on one of the three. No
    // text-field guard, deliberately — Ctrl/Cmd+N is not a text-editing
    // binding on any of the three platforms (Flutter binds Ctrl+N to
    // "line down" only in its macOS Emacs set, and there we send Cmd+N), so
    // consuming it while the search field has focus costs nothing and firing
    // it there is what every desktop app does.
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        SingleActivator(
          LogicalKeyboardKey.keyF,
          control: !Platform.isMacOS,
          meta: Platform.isMacOS,
        ): _searchFocusNode.requestFocus,
        SingleActivator(
          LogicalKeyboardKey.keyN,
          control: !Platform.isMacOS,
          meta: Platform.isMacOS,
        ): widget.onAdd,
      },
      // `skipTraversal` so this wrapper never becomes a Tab stop of its own;
      // it exists only to give the shortcut a focused descendant to bubble
      // from, exactly as `SettingsPage` does it — and, since it is the one
      // node that is an ancestor of both the search field and the list, to
      // carry the arrow-cursor's bare keys (see `_handlePageKeyEvent`).
      child: Focus(
        autofocus: true,
        skipTraversal: true,
        onKeyEvent: _handlePageKeyEvent,
        child: WpPageShell(
          scrollable: false,
          padding: EdgeInsets.zero,
          child: (widget.header == null && subtitleLine == null)
              ? body
              : LayoutBuilder(
                  // Von *außen* gemessen: ein Column-Kind ohne Flex bekommt in
                  // der Hauptachse unbegrenzte Constraints und weiß deshalb
                  // selbst nicht, wie viel Platz die Seite überhaupt hat.
                  builder: (context, constraints) => Column(
                    children: [
                      ?subtitleLine,
                      if (widget.header case final header?)
                        _cappedHeader(header, constraints.maxHeight),
                      Expanded(child: body),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  /// Keeps [header] from ever eating the list below it.
  ///
  /// The header is the one child of this page that is *not* flexible, so a
  /// header taller than the window leaves the list exactly zero pixels —
  /// which is not a cosmetic overflow but a page whose entire content is
  /// gone. Reachable in practice since the Snippets header carries two
  /// settings (ticket 27): measured at accessibility text size 2.0 in an
  /// 800×600 window it overshot by 43 px, and every further step of the
  /// system font size makes it worse.
  ///
  /// Above the cap the header scrolls inside its own share instead. A second
  /// scroll area is not free, but it only ever appears where the alternative
  /// is a blank page — at every ordinary text size the header is far shorter
  /// than the cap and this wrapper changes nothing (the scroll view takes its
  /// child's height while it fits).
  ///
  /// The cap is „everything except what the list needs to exist": the search
  /// toolbar plus one row, scaled with the system font size, because that is
  /// what grows underneath the header in the first place. A fixed fraction
  /// does not work in both directions — a third of the window clips the
  /// Snippets header at normal text size, and half of it still buries the
  /// toolbar at 2.5.
  Widget _cappedHeader(Widget header, double availableHeight) {
    if (!availableHeight.isFinite) return header;
    final reserved = MediaQuery.textScalerOf(
      context,
    ).scale(_searchableListBodyReserve);
    return ConstrainedBox(
      constraints: BoxConstraints(
        // Nie unter ein Viertel der Seite: lieber ein knapper, scrollender
        // Kopfbereich als einer, der auf eine Zeile zusammenfällt.
        maxHeight: math.max(availableHeight - reserved, availableHeight / 4),
      ),
      child: SingleChildScrollView(child: header),
    );
  }
}

/// Shared delete-confirmation flow of the searchable-list features: shows the
/// standard destructive [showWpConfirmDialog] (Delete / Cancel labels) and
/// runs [onConfirm] only when the user confirmed.
Future<void> showWpDeleteConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  required VoidCallback onConfirm,
}) async {
  final l10n = L10n.of(context);
  final confirmed = await showWpConfirmDialog(
    context: context,
    title: title,
    message: message,
    confirmLabel: l10n.actionDelete,
    cancelLabel: l10n.actionCancel,
    destructive: true,
  );
  if (confirmed) onConfirm();
}
