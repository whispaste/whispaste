import 'package:flutter/material.dart';

import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import 'wp_head_actions.dart';

// ---------------------------------------------------------------------------
// WpContextMenu — the right-click menu of a list row (#1498).
//
// Recordings, notes and snippets each opened their own `showMenu` with bare
// text items, while the "…" menu in the editor head already drew icon rows
// ([WpMenuRow]). Two menus for the same item looked like two products. Now
// every row menu goes through [showWpContextMenu]: the same surface as the
// head menu, one [WpMenuRow] per entry (icon, regular weight), and the
// destructive entries last, after a divider, in the error colour.
// ---------------------------------------------------------------------------

/// One entry of a row's context menu.
class WpContextMenuEntry {
  const WpContextMenuEntry({
    this.key,
    required this.icon,
    required this.label,
    required this.onSelected,
    this.destructive = false,
  });

  /// Key of the menu item, so flows can address it (`<screen>-<action>-<id>`).
  final Key? key;
  final IconData icon;
  final String label;
  final VoidCallback onSelected;

  /// Deletes or discards something: drawn in the error colour, placed last
  /// after a divider.
  final bool destructive;
}

/// Opens the shared row context menu at [globalPosition] and runs the chosen
/// entry's callback. Does nothing for an empty [entries] list.
Future<void> showWpContextMenu(
  BuildContext context, {
  required Offset globalPosition,
  required List<WpContextMenuEntry> entries,
}) async {
  if (entries.isEmpty) return;
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final safe = [
    for (final e in entries)
      if (!e.destructive) e,
  ];
  final destructive = [
    for (final e in entries)
      if (e.destructive) e,
  ];
  PopupMenuItem<VoidCallback> item(WpContextMenuEntry e) => PopupMenuItem(
    key: e.key,
    value: e.onSelected,
    child: WpMenuRow(
      icon: e.icon,
      label: e.label,
      isDestructive: e.destructive,
    ),
  );
  final choice = await showMenu<VoidCallback>(
    context: context,
    position: RelativeRect.fromRect(
      globalPosition & Size.zero,
      Offset.zero & overlay.size,
    ),
    // Same floating surface and radius as the editor head's "…" menu.
    color: WpColors.floatingSurface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(WpRadius.md),
    ),
    items: [
      for (final e in safe) item(e),
      if (safe.isNotEmpty && destructive.isNotEmpty) const PopupMenuDivider(),
      for (final e in destructive) item(e),
    ],
  );
  choice?.call();
}
