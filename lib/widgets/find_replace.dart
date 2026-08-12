/// Find-and-replace *inside one text field* — the string engine and the
/// controller that paints its hits.
///
/// Deliberately not the same feature as any of the app's search fields
/// ([WpSearchField], the History search bar, Settings search): those narrow a
/// *list* by typing and never touch the text they find. This one rewrites the
/// content of the field it is pointed at and knows nothing about lists. The
/// `findReplace*` ARB keys keep the two apart in the UI copy as well.
///
/// Split in two on purpose: everything here is either a pure string operation
/// or a [TextEditingController], so all four behaviours the feature promises
/// (locate, navigate, replace one, replace all) are unit-testable without
/// pumping a widget. The bar that drives it lives in `find_replace_bar.dart`.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../core/theme/colors.dart';

/// Where every occurrence of a query sits in a piece of text.
///
/// Offsets are start indices into the text they were located in; every match
/// is [length] characters long, because the query is matched literally. They
/// go stale the moment the text changes — [WpFindHighlightController] checks
/// them against the current text before painting rather than trusting them.
@immutable
class WpFindMatches {
  const WpFindMatches({required this.starts, required this.length});

  /// No query, no hits — the state a closed or empty find bar is in.
  static const WpFindMatches none = WpFindMatches(starts: <int>[], length: 0);

  /// Start offsets, ascending, non-overlapping.
  final List<int> starts;

  /// Length of the query every entry in [starts] matched.
  final int length;

  int get count => starts.length;
  bool get isEmpty => starts.isEmpty;
  bool get isNotEmpty => starts.isNotEmpty;

  /// End offset (exclusive) of the match at [index].
  int endOf(int index) => starts[index] + length;

  bool sameAs(WpFindMatches other) =>
      length == other.length && listEquals(starts, other.starts);
}

/// The string half of find-and-replace: locate, replace one, replace all.
///
/// Literal matching only — never `RegExp(query)`. A user typing `(` into a
/// find field is typing a parenthesis, not an unbalanced capture group, and
/// the regex would throw on them mid-keystroke.
abstract final class WpFindReplace {
  /// Every non-overlapping occurrence of [query] in [text], left to right.
  ///
  /// Case-insensitive by default, via a lowercased copy of both sides. That
  /// copy is only trusted when it is the *same length* as its original:
  /// a handful of code points (Turkish `İ`, for one) lowercase into more
  /// characters than they came from, which would shift every offset after
  /// them onto the wrong character. Where that happens the search silently
  /// falls back to matching case-sensitively — a couple of missed hits beats
  /// replacing the wrong span of text.
  static WpFindMatches locate(
    String text,
    String query, {
    bool caseSensitive = false,
  }) {
    if (query.isEmpty || text.isEmpty) return WpFindMatches.none;

    var haystack = text;
    var needle = query;
    if (!caseSensitive) {
      final lowerText = text.toLowerCase();
      final lowerQuery = query.toLowerCase();
      if (lowerText.length == text.length &&
          lowerQuery.length == query.length) {
        haystack = lowerText;
        needle = lowerQuery;
      }
    }

    final starts = <int>[];
    var index = haystack.indexOf(needle);
    while (index != -1) {
      starts.add(index);
      // Step past the whole match: overlapping hits ("aa" in "aaa") would
      // make replace-all produce text that depends on iteration order.
      index = haystack.indexOf(needle, index + needle.length);
    }
    if (starts.isEmpty) return WpFindMatches.none;
    return WpFindMatches(
      starts: List<int>.unmodifiable(starts),
      length: query.length,
    );
  }

  /// [text] with the single match at [index] swapped for [replacement].
  ///
  /// Returns [text] untouched when [index] points nowhere or the offsets no
  /// longer fit the text — a caller holding stale matches must not be able to
  /// cut a hole in the middle of a word.
  static String replaceOne(
    String text,
    WpFindMatches matches,
    int index,
    String replacement,
  ) {
    if (index < 0 || index >= matches.count) return text;
    final start = matches.starts[index];
    final end = matches.endOf(index);
    if (end > text.length) return text;
    return text.replaceRange(start, end, replacement);
  }

  /// [text] with every match swapped for [replacement], in one pass.
  ///
  /// One pass rather than a loop of [replaceOne] for two reasons: the offsets
  /// after each edit would all need re-deriving, and a replacement that
  /// contains the query (`a` → `aa`) would otherwise be re-found and replaced
  /// again, forever.
  static String replaceAll(
    String text,
    WpFindMatches matches,
    String replacement,
  ) {
    if (matches.isEmpty) return text;
    if (matches.starts.last + matches.length > text.length) return text;

    final buffer = StringBuffer();
    var cursor = 0;
    for (final start in matches.starts) {
      if (start < cursor) return text; // overlapping / unsorted: refuse
      buffer
        ..write(text.substring(cursor, start))
        ..write(replacement);
      cursor = start + matches.length;
    }
    buffer.write(text.substring(cursor));
    return buffer.toString();
  }

  /// The match index to sit on after the text changed under an open find bar.
  ///
  /// Clamps into the new match list and answers `-1` when nothing is left, so
  /// callers never have to spell the same three edge cases out again.
  static int clampIndex(int index, int count) {
    if (count == 0) return -1;
    if (index < 0) return 0;
    return index >= count ? count - 1 : index;
  }
}

/// A [TextEditingController] that can tint the hits of a find query.
///
/// Needed because a [TextField] only paints its selection **while focused**
/// (`TextField` passes `selectionColor: focusNode.hasFocus ? … : null`), and
/// the whole point of a find bar is that focus is in the *find field* while
/// the user reads the hits in the body. Moving `controller.selection` alone
/// would therefore highlight nothing at the exact moment it matters.
///
/// Opt-in: the bar works against a plain [TextEditingController] too — it just
/// counts, navigates and replaces without the tint. Every surface that hosts
/// [WpMarkdownToolbar] (History's transcript editor, the Notes editor, the
/// Snippet dialog) opts in by constructing this instead.
///
/// **Note for owners of the controller:** [setFindHighlight] calls
/// `notifyListeners()` without the text having changed, because that is the
/// only thing a [TextField] rebuilds on. A listener that writes on every
/// notification (an autosave, say) must compare the text first.
class WpFindHighlightController extends TextEditingController {
  WpFindHighlightController({super.text});

  WpFindMatches _matches = WpFindMatches.none;
  int _activeIndex = -1;

  WpFindMatches get findMatches => _matches;

  /// Index into [findMatches] drawn in the stronger tint, or `-1` for none.
  int get activeFindIndex => _activeIndex;

  /// Points the highlight at [matches], emphasising [activeIndex].
  ///
  /// A no-op when nothing actually changed — without that guard the bar's own
  /// "recompute on controller change" listener would answer this notification
  /// with another identical one, forever.
  void setFindHighlight(WpFindMatches matches, int activeIndex) {
    if (activeIndex == _activeIndex && matches.sameAs(_matches)) return;
    _matches = matches;
    _activeIndex = activeIndex;
    notifyListeners();
  }

  void clearFindHighlight() => setFindHighlight(WpFindMatches.none, -1);

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final matches = _matches;
    final text = value.text;

    // Hand back to the default painter when there is nothing to tint, when the
    // offsets no longer fit the text (one frame of staleness between an edit
    // and the bar's recompute), or mid-IME-composition — the composing
    // underline is the more important signal while a character is being
    // assembled.
    final composing = withComposing && value.isComposingRangeValid;
    if (matches.isEmpty ||
        composing ||
        matches.starts.last + matches.length > text.length) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }

    final children = <InlineSpan>[];
    var cursor = 0;
    for (var i = 0; i < matches.count; i++) {
      final start = matches.starts[i];
      final end = matches.endOf(i);
      if (start < cursor) {
        return super.buildTextSpan(
          context: context,
          style: style,
          withComposing: withComposing,
        );
      }
      if (start > cursor) {
        children.add(TextSpan(text: text.substring(cursor, start)));
      }
      children.add(
        TextSpan(
          text: text.substring(start, end),
          style: TextStyle(
            backgroundColor: WpColors.accent.withValues(
              alpha: i == _activeIndex ? 0.45 : 0.16,
            ),
          ),
        ),
      );
      cursor = end;
    }
    if (cursor < text.length) {
      children.add(TextSpan(text: text.substring(cursor)));
    }

    return TextSpan(style: style, children: children);
  }
}
