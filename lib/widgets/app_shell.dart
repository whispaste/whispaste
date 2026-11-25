import 'package:flutter/material.dart';

/// The window's layout (ticket, chat-08): the title band across the top, the
/// sidebar running the full height below it, and the content panel beside it.
///
/// The recording dock lives inside the content panel, under the page, so it
/// floats over the content column only and never under the sidebar; the dock
/// brings its own 12 px inset from the panel's edges.
///
/// Title band, sidebar and content panel are separate focus traversal groups
/// (#1845): Tab walks the whole sidebar before it enters the page. Without
/// the groups, reading order mixed both columns row by row, so focus jumped
/// from a sidebar entry into the page and back.
class WpAppShell extends StatelessWidget {
  const WpAppShell({
    super.key,
    required this.titleBar,
    required this.sidebar,
    required this.content,
    required this.dock,
    this.contentDecoration,
    this.focusMode = false,
  });

  /// The window's title band, above the sidebar and the panel.
  final Widget titleBar;

  /// The navigation rail, full height below the title band.
  final Widget sidebar;

  /// The page: header, then the page body. It fills the panel above the dock.
  final Widget content;

  /// The recording dock, pinned to the panel's bottom edge.
  final Widget dock;

  /// Paint of the content panel (the surface the page stands on).
  final Decoration? contentDecoration;

  /// Focus mode of the note editor (#669): the title band and the sidebar
  /// step aside so the page fills the window. They keep their state and come
  /// back unchanged; the dock stays, dictating is part of writing.
  final bool focusMode;

  @override
  Widget build(BuildContext context) {
    // Fixed region order (#1845): title band, sidebar, page, dock. Inside a
    // region the reading order applies. Without the outer order the dock,
    // pinned under the page, sorted between page controls that scroll below
    // it, so Tab kept jumping into the dock and back.
    return FocusTraversalGroup(
      policy: WidgetOrderTraversalPolicy(),
      child: Column(
        children: [
          Visibility(
            visible: !focusMode,
            maintainState: true,
            child: FocusTraversalGroup(child: titleBar),
          ),
          Expanded(
            child: Row(
              children: [
                Visibility(
                  visible: !focusMode,
                  maintainState: true,
                  child: FocusTraversalGroup(child: sidebar),
                ),
                Expanded(
                  child: FocusTraversalGroup(
                    policy: WidgetOrderTraversalPolicy(),
                    child: Container(
                      decoration: contentDecoration,
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          Expanded(child: FocusTraversalGroup(child: content)),
                          FocusTraversalGroup(child: dock),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
