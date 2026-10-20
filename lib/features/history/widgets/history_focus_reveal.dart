import 'package:flutter/widgets.dart';

import 'history_helpers.dart';

/// Keeps the keyboard-focused history row on screen (UIA-HIS-04).
///
/// A `ListView.builder` only builds rows near the viewport, so a focused row
/// that is off screen has no context to scroll to. [schedule] steps toward it
/// one viewport at a time, using the built rows to pick the direction, until
/// the row is built, and then scrolls it into view.
class HistoryFocusReveal {
  final ScrollController scroll = ScrollController();
  final Map<String, GlobalKey> _rowKeys = {};
  bool _disposed = false;

  /// Rough row pitch, used only to pick the scroll direction when no row is
  /// built yet.
  static const _estimatedRowExtent = 72.0;

  /// Key for a row. Pass it to the row widget so the reveal can find it.
  GlobalKey keyFor(String id) => _rowKeys.putIfAbsent(id, GlobalKey.new);

  /// Wraps a row in a subtree carrying its [keyFor] key, so the row itself
  /// keeps its `ValueKey(entry.id)` that callers and tests look rows up by.
  Widget wrap(String id, Widget row) =>
      KeyedSubtree(key: keyFor(id), child: row);

  /// Schedules a reveal after the current frame. Call when focus moves.
  void schedule(List<HistoryFlatItem> flat, String? focusedId) {
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _reveal(flat, focusedId, 0),
    );
  }

  void _reveal(List<HistoryFlatItem> flat, String? id, int attempt) {
    if (_disposed || id == null) return;
    final rowContext = _rowKeys[id]?.currentContext;
    if (rowContext != null) {
      Scrollable.ensureVisible(
        rowContext,
        duration: const Duration(milliseconds: 120),
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
      return;
    }
    final index = flat.indexWhere((i) => i.entry?.id == id);
    if (index < 0 || attempt > 200 || !scroll.hasClients) return;
    int? lastBuilt;
    for (var i = 0; i < flat.length; i++) {
      final entry = flat[i].entry;
      if (entry != null && _rowKeys[entry.id]?.currentContext != null) {
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
      (_) => _reveal(flat, id, attempt + 1),
    );
  }

  void dispose() {
    _disposed = true;
    scroll.dispose();
  }
}
