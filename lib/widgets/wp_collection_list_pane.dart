import 'package:flutter/widgets.dart';

import '../core/theme/tokens.dart';
import 'page_shell.dart';
import 'wp_copy_feedback.dart';

/// One row of a [WpCollectionListPane]: a group header or an item.
sealed class WpCollectionRow<T> {
  const WpCollectionRow();
}

/// A group header (date, favourites, "other notes"). The header widget owns
/// its look and semantics; the pane only places it.
final class WpCollectionHeaderRow<T> extends WpCollectionRow<T> {
  const WpCollectionHeaderRow(this.header);
  final Widget header;
}

/// An item row, identified by [id] for selection, copy feedback and the
/// keyboard cursor's reveal.
final class WpCollectionItemRow<T> extends WpCollectionRow<T> {
  const WpCollectionItemRow(this.id, this.item);
  final String id;
  final T item;
}

/// The left column of every collection page (Recordings, Notes, Snippets;
/// #1498).
///
/// Owns what used to be repeated per feature: the page inset on both sides
/// (so rows line up with the toolbar above), the gap between rows, the copy
/// anchor of each row, the scroll offset that survives a page switch, and
/// keeping the keyboard cursor's row on screen. Features hand in rows and
/// build the tile; group headers come in as rows of their own.
class WpCollectionListPane<T> extends StatefulWidget {
  const WpCollectionListPane({
    super.key,
    required this.storageKey,
    required this.copyTargetPrefix,
    required this.rows,
    required this.itemBuilder,
    this.focusedId,
    this.revealId,
    this.focusNode,
    this.placeholder,
    this.leading,
    this.rowGap = WpSpacing.xs,
    this.semanticsLabel,
    this.semanticsIdentifier,
  });

  /// [PageStorageKey] value, so the scroll offset survives a page switch
  /// (#1074).
  final String storageKey;

  /// Copy-feedback target is `<copyTargetPrefix>-<id>`.
  final String copyTargetPrefix;
  final List<WpCollectionRow<T>> rows;
  final Widget Function(BuildContext context, T item) itemBuilder;

  /// The keyboard cursor's row; scrolled into view whenever it changes,
  /// minimally and in the direction the cursor moved.
  final String? focusedId;

  /// A row to bring to the middle of the list once, e.g. an entry that was
  /// just saved or restored. Scrolled to whenever the value changes.
  final String? revealId;

  /// The list node of a [WpCollectionSelection]: mounted on a
  /// `skipTraversal` [Focus] around the list, so it is a target of the
  /// keyboard cursor and never a Tab stop.
  final FocusNode? focusNode;

  /// Replaces the rows while there are none to show (loading, error, empty,
  /// no matches). Fills the room under [leading] in the same scroll owner,
  /// so [leading] stays where it is between the states. Page hints (what the
  /// page is for, where its settings live) belong in this empty state, not
  /// above the rows.
  final Widget? placeholder;

  /// A tool that scrolls with the rows, above the first one (the audio
  /// import of Recordings). Not for explanatory text: see [placeholder].
  final Widget? leading;

  /// Gap under each item row. Only the dense list mode of Recordings passes
  /// zero; everything else keeps the default.
  final double rowGap;

  /// Names the list for screen readers (`<screen>-list`).
  final String? semanticsLabel;
  final String? semanticsIdentifier;

  /// Inset of the list: page inset left and right, a small top, room for the
  /// dock at the bottom.
  static const EdgeInsets padding = EdgeInsets.fromLTRB(
    WpPageFrame.inset,
    WpSpacing.xs,
    WpPageFrame.inset,
    WpSpacing.xxl,
  );

  @override
  State<WpCollectionListPane<T>> createState() =>
      _WpCollectionListPaneState<T>();
}

class _WpCollectionListPaneState<T> extends State<WpCollectionListPane<T>> {
  final WpListFocusReveal _reveal = WpListFocusReveal();

  @override
  void didUpdateWidget(covariant WpCollectionListPane<T> old) {
    super.didUpdateWidget(old);
    final ids = _ids;
    final focused = widget.focusedId;
    if (focused != null && focused != old.focusedId) {
      // Upward travel keeps the row at the top edge, downward at the bottom.
      final from = old.focusedId == null ? -1 : ids.indexOf(old.focusedId);
      final up = from >= 0 && ids.indexOf(focused) < from;
      _reveal.schedule(ids, focused, upward: up);
    }
    final reveal = widget.revealId;
    if (reveal != null && reveal != old.revealId) {
      _reveal.schedule(ids, reveal, centre: true);
    }
  }

  @override
  void initState() {
    super.initState();
    final reveal = widget.revealId;
    if (reveal != null) _reveal.schedule(_ids, reveal, centre: true);
  }

  List<String?> get _ids => [
    for (final row in widget.rows)
      switch (row) {
        WpCollectionItemRow<T>(:final id) => id,
        WpCollectionHeaderRow<T>() => null,
      },
  ];

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final leading = widget.leading;
    final rows = widget.rows;
    final placeholder = widget.placeholder;
    final Widget list = placeholder != null
        ? CustomScrollView(
            key: PageStorageKey<String>(widget.storageKey),
            controller: _reveal.scroll,
            slivers: [
              if (leading != null)
                SliverPadding(
                  padding: WpCollectionListPane.padding.copyWith(bottom: 0),
                  sliver: SliverToBoxAdapter(child: leading),
                ),
              SliverFillRemaining(child: placeholder),
            ],
          )
        : ListView.builder(
            key: PageStorageKey<String>(widget.storageKey),
            controller: _reveal.scroll,
            padding: WpCollectionListPane.padding,
            itemCount: rows.length + (leading == null ? 0 : 1),
            itemBuilder: (context, i) {
              if (leading != null) {
                if (i == 0) return leading;
                i--;
              }
              return switch (rows[i]) {
                WpCollectionHeaderRow<T>(:final header) => header,
                WpCollectionItemRow<T>(:final id, :final item) => _reveal.wrap(
                  id,
                  Padding(
                    padding: EdgeInsets.only(bottom: widget.rowGap),
                    child: WpCopyAnchor(
                      target: '${widget.copyTargetPrefix}-$id',
                      child: widget.itemBuilder(context, item),
                    ),
                  ),
                ),
              };
            },
          );
    final focusNode = widget.focusNode;
    final focusable = focusNode == null
        ? list
        : Focus(focusNode: focusNode, skipTraversal: true, child: list);
    if (widget.semanticsLabel == null && widget.semanticsIdentifier == null) {
      return focusable;
    }
    return Semantics(
      label: widget.semanticsLabel,
      identifier: widget.semanticsIdentifier,
      child: focusable,
    );
  }
}

/// Keeps the keyboard-focused row of a lazily built list on screen.
///
/// A `ListView.builder` only builds rows near the viewport, so a focused row
/// that is off screen has no context to scroll to. [schedule] steps toward it
/// one viewport at a time, using the built rows to pick the direction, until
/// the row is built, and then scrolls it into view.
class WpListFocusReveal {
  final ScrollController scroll = ScrollController();
  final Map<String, GlobalKey> _rowKeys = {};
  bool _disposed = false;

  /// Rough row pitch, used only to pick the scroll direction when no row is
  /// built yet.
  static const _estimatedRowExtent = 72.0;

  GlobalKey _keyFor(String id) => _rowKeys.putIfAbsent(id, GlobalKey.new);

  /// Wraps a row in a subtree carrying its reveal key, so the row itself
  /// keeps the `ValueKey(id)` callers and tests look rows up by. Every row
  /// is wrapped, so the structure stays constant as the cursor moves.
  Widget wrap(String id, Widget row) =>
      KeyedSubtree(key: _keyFor(id), child: row);

  /// Schedules a reveal after the current frame. [ids] holds one entry per
  /// list row in order, null for headers.
  ///
  /// By default the row scrolls in minimally, at the bottom edge; [upward]
  /// keeps it at the top edge instead (the cursor moved up), [centre] brings
  /// it to the middle (a row the page points at, not one the cursor stepped
  /// onto).
  void schedule(
    List<String?> ids,
    String? focusedId, {
    bool upward = false,
    bool centre = false,
  }) {
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _reveal(ids, focusedId, 0, upward: upward, centre: centre),
    );
  }

  void _reveal(
    List<String?> ids,
    String? id,
    int attempt, {
    required bool upward,
    required bool centre,
  }) {
    if (_disposed || id == null) return;
    final rowContext = _rowKeys[id]?.currentContext;
    if (rowContext != null) {
      if (centre) {
        Scrollable.ensureVisible(
          rowContext,
          alignment: 0.5,
          duration: WpMotion.durationFor(rowContext, WpMotion.normal),
        );
      } else {
        Scrollable.ensureVisible(
          rowContext,
          duration: WpMotion.durationFor(rowContext, WpMotion.fast),
          alignmentPolicy: upward
              ? ScrollPositionAlignmentPolicy.keepVisibleAtStart
              : ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        );
      }
      return;
    }
    final index = ids.indexOf(id);
    if (index < 0 || attempt > 200 || !scroll.hasClients) return;
    int? lastBuilt;
    for (var i = 0; i < ids.length; i++) {
      final rowId = ids[i];
      if (rowId != null && _rowKeys[rowId]?.currentContext != null) {
        lastBuilt = i;
      }
    }
    final position = scroll.position;
    // With no row built yet, compare against a rough row pitch instead.
    final down = lastBuilt == null
        ? index * _estimatedRowExtent > position.pixels
        : index > lastBuilt;
    final step = position.viewportDimension * 0.8;
    scroll.jumpTo(
      (position.pixels + (down ? step : -step)).clamp(
        0.0,
        position.maxScrollExtent,
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _reveal(ids, id, attempt + 1, upward: upward, centre: centre),
    );
  }

  void dispose() {
    _disposed = true;
    scroll.dispose();
  }
}
