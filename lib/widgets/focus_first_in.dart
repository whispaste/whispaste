import 'package:flutter/widgets.dart';

/// Moves keyboard focus to the first control inside [area], in reading order
/// (top to bottom, then start to end of the line).
///
/// For navigation that changes the page without a click (Ctrl+, opens
/// Settings, F1 opens Help, #1845): without it focus stayed on the sidebar
/// entry the user had left, and the next Tab continued from there.
///
/// Returns false when [area] holds no focusable control yet; focus is then
/// left where it is.
bool focusFirstIn(FocusNode area) {
  final context = area.context;
  if (context == null || !context.mounted) return false;
  final rtl = Directionality.maybeOf(context) == TextDirection.rtl;
  FocusNode? best;
  for (final node in area.traversalDescendants) {
    if (!node.canRequestFocus || node.context == null) continue;
    final rect = node.rect;
    if (rect.isEmpty) continue;
    if (best == null || _before(rect, best.rect, rtl)) best = node;
  }
  if (best == null) return false;
  best.requestFocus();
  return true;
}

/// Same visual line when the vertical centres lie within half the smaller
/// height of each other; otherwise the higher one comes first.
bool _before(Rect a, Rect b, bool rtl) {
  final sameLine =
      (a.center.dy - b.center.dy).abs() <
      (a.height < b.height ? a.height : b.height) / 2;
  if (!sameLine) return a.top < b.top;
  return rtl ? a.right > b.right : a.left < b.left;
}
