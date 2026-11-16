import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/search/search_ranker.dart';
import '../core/utils/focus_helpers.dart';

// ---------------------------------------------------------------------------
// The keyboard cursor of a collection list
//
// Replacements and Snippets used to be reachable by Tab and nothing else: at
// 40 entries, "open the third one" cost 40 keystrokes, on the two screens
// whose whole point is a list you maintain. Verlauf and Notizen have had an
// arrow cursor since they existed, so this was the one keyboard skill that
// stopped working halfway across the app.
//
// The model is *rebuilt* from Verlauf/Notizen (`internal-notes` §5.9), not
// imported: one page-level index into the **filtered** list, rendered by the
// rows and moved by the page. What differs, and why:
//
//   * **Entry point.** In Verlauf/Notizen every bare key is dropped while a
//     text field has focus. Here the search field *is* the way in — it holds
//     focus the moment the page opens — so ArrowDown is deliberately not
//     guarded: it takes the caret out of the field and puts the cursor on the
//     first row. Escape is the way back. Everything else (Enter, Delete,
//     Backspace, Space) only fires while the cursor is live, i.e. while focus
//     sits on the list node and no text field can be typing.
//   * **Scrolling.** A full-width page list is long, so the cursor row is
//     scrolled into view, minimally and in the direction of travel. The
//     owning list does the scrolling; this controller only says when.
//
// One highlight at a time is structural rather than remembered: the index is
// only rendered while [WpCollectionSelection.listFocusNode] holds *primary*
// focus. Tab moves focus into a row itself, the list node stops being
// primary, and the cursor stops painting — so the row's own focus treatment
// is never in competition with it. The index survives, which is what makes
// Enter → dialog → close return to row 20 instead of to the top.
// ---------------------------------------------------------------------------

/// Search query, keyboard cursor and the bare-key handling of a collection
/// list (#1498): arrows and J/K move the cursor, Enter activates, Delete or
/// Backspace deletes, Space toggles the multi-select, Escape hands back to
/// the search field.
///
/// Owned by the page's state (create once, [dispose] with it). The page
/// mounts [searchFocusNode] on its search field, [listFocusNode] on a
/// `skipTraversal` [Focus] around the list, and routes the page-level
/// `onKeyEvent` into [handleKey]. Listeners fire on every change of query,
/// cursor or list focus, so the page rebuilds with `setState`.
class WpCollectionSelection<T> extends ChangeNotifier {
  WpCollectionSelection({String debugLabel = 'WpCollectionSelection'})
    : searchFocusNode = FocusNode(debugLabel: '$debugLabel search'),
      listFocusNode = FocusNode(debugLabel: '$debugLabel list') {
    listFocusNode.addListener(_onListFocusChanged);
  }

  final TextEditingController searchController = TextEditingController();
  final FocusNode searchFocusNode;

  /// Holds real focus while the arrow cursor is live. `skipTraversal` where
  /// it is mounted: it is a target of [FocusNode.requestFocus], never a Tab
  /// stop, so the row-by-row Tab order it sits in front of is unchanged.
  final FocusNode listFocusNode;

  String _query = '';
  int _cursorIndex = -1;
  bool _listHasPrimaryFocus = false;

  String get query => _query;

  /// Index into the *filtered* list, or -1 for "no cursor". Rendered only
  /// while [listFocusNode] has primary focus — see [cursorIn].
  int get cursorIndex => _cursorIndex;

  void _onListFocusChanged() {
    if (_listHasPrimaryFocus == listFocusNode.hasPrimaryFocus) return;
    _listHasPrimaryFocus = listFocusNode.hasPrimaryFocus;
    notifyListeners();
  }

  /// The search field's `onChanged`. Every keystroke re-filters, so the index
  /// the cursor held points at a different item: it is dropped.
  void setQuery(String value) {
    _query = value;
    _cursorIndex = -1;
    notifyListeners();
  }

  /// Resets the search from outside the field (the no-matches empty state,
  /// Escape). [TextEditingController] fires no `onChanged`, so the query is
  /// reset alongside the text.
  void clearSearch() {
    searchController.clear();
    setQuery('');
  }

  /// Matches ranked by the app's one search ([rankSearch]): title hits
  /// before body hits, ties in the list's own order.
  List<T> filter(List<T> all, List<SearchField> Function(T item) fields) {
    if (_query.trim().isEmpty) return all;
    final hits = rankSearch([
      for (var i = 0; i < all.length; i++) SearchDoc('$i', fields(all[i])),
    ], _query);
    return [for (final h in hits) all[h.index]];
  }

  /// The rendered cursor in [visible], or -1. Derived, never stored: an item
  /// can be deleted out from under the cursor between two frames.
  int cursorIn(List<T> visible) =>
      _listHasPrimaryFocus && _cursorIndex >= 0 && _cursorIndex < visible.length
      ? _cursorIndex
      : -1;

  /// The item under the cursor, or null when the cursor is not live — which
  /// is also the guard that keeps Enter/Delete from firing while the caret is
  /// in the search field.
  T? cursorItem(List<T> visible) {
    final i = cursorIn(visible);
    return i < 0 ? null : visible[i];
  }

  /// Moves the cursor by [delta], or places it when it is not live yet:
  /// ArrowDown enters at the top, ArrowUp at the bottom. Clamps at both ends
  /// rather than wrapping, so the first and last row stay a place you can
  /// arrive at and stop. [onReveal] runs after the frame that paints it.
  KeyEventResult moveCursor(
    int delta,
    List<T> visible, {
    void Function(int delta)? onReveal,
  }) {
    if (visible.isEmpty) return KeyEventResult.ignored;
    final live = _listHasPrimaryFocus && _cursorIndex >= 0;
    _cursorIndex = live
        ? (_cursorIndex + delta).clamp(0, visible.length - 1)
        : (delta > 0 ? 0 : visible.length - 1);
    notifyListeners();
    // Before the frame, so the row is already the cursor when it is revealed.
    listFocusNode.requestFocus();
    if (onReveal != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => onReveal(delta));
    }
    return KeyEventResult.handled;
  }

  /// Escape: hand the caret back to the search field and drop the cursor.
  void returnToSearch() {
    _cursorIndex = -1;
    notifyListeners();
    searchFocusNode.requestFocus();
  }

  /// True when a text input other than the page's search field has focus.
  bool foreignTextFieldHasFocus() {
    final focused = FocusManager.instance.primaryFocus;
    if (focused == null || focused == searchFocusNode) return false;
    return focused.context?.findAncestorStateOfType<EditableTextState>() !=
        null;
  }

  /// Bare-key handler for the whole page, mounted on a [Focus] that is an
  /// ancestor of both the search field and the list — so the keys arrive
  /// wherever focus sits, also on a page that has just opened.
  ///
  /// Runs *below* the app-level [DefaultTextEditingShortcuts], which is why
  /// ArrowUp/ArrowDown reach it while the search field has focus. The price
  /// is that those two keys no longer jump the caret to the start/end of the
  /// query — a single-line field, where Home/End say the same thing.
  ///
  /// [onEscape] returns true when the page consumed Escape itself (leave the
  /// selection, close the detail); otherwise Escape clears the search or
  /// returns to it.
  KeyEventResult handleKey(
    KeyEvent event, {
    required List<T> visible,
    required void Function(T item) onActivate,
    void Function(T item)? onDelete,
    void Function(T item)? onToggleSelect,
    bool Function()? onEscape,
    void Function(int delta)? onReveal,
  }) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    // A text field elsewhere on the page (the Snippets trigger field, for one)
    // owns its arrows and Escape. Only the page's own search field may pass.
    if (foreignTextFieldHasFocus()) return KeyEventResult.ignored;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.arrowDown) {
      return moveCursor(1, visible, onReveal: onReveal);
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      return moveCursor(-1, visible, onReveal: onReveal);
    }
    // Bare J/K step like the arrows (shared list keyset, listStepFor), but
    // never while the search field has focus: there they are letters.
    if (!isTextFieldFocused()) {
      final step = listStepFor(key);
      if (step != null) return moveCursor(step, visible, onReveal: onReveal);
    }

    // Everything below acts on the cursor's row, so it is inert unless the
    // cursor is live — which also means no text field can have focus.
    final item = cursorItem(visible);
    if (item == null) {
      if (key == LogicalKeyboardKey.escape && (onEscape?.call() ?? false)) {
        return KeyEventResult.handled;
      }
      // Escape outside the cursor clears a live search; the field keeps focus.
      if (key == LogicalKeyboardKey.escape && _query.isNotEmpty) {
        clearSearch();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (key == LogicalKeyboardKey.enter) {
      onActivate(item);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      // Same keys as the per-row binding for Tab focus — the cursor row
      // simply has no focused descendant for that binding to fire from.
      onDelete?.call(item);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.space && onToggleSelect != null) {
      onToggleSelect(item);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      if (onEscape?.call() ?? false) return KeyEventResult.handled;
      returnToSearch();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    listFocusNode.removeListener(_onListFocusChanged);
    searchController.dispose();
    searchFocusNode.dispose();
    listFocusNode.dispose();
    super.dispose();
  }
}
