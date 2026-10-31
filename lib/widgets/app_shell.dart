import 'package:flutter/material.dart';

/// The window's layout (WP-20, chat-08): the title band across the top, the
/// sidebar running the full height below it, and the content panel beside it.
///
/// The recording dock lives inside the content panel, under the page, so it
/// floats over the content column only and never under the sidebar; the dock
/// brings its own 12 px inset from the panel's edges.
class WpAppShell extends StatelessWidget {
  const WpAppShell({
    super.key,
    required this.titleBar,
    required this.sidebar,
    required this.content,
    required this.dock,
    this.contentDecoration,
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

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        titleBar,
        Expanded(
          child: Row(
            children: [
              sidebar,
              Expanded(
                child: Container(
                  decoration: contentDecoration,
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      Expanded(child: content),
                      dock,
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
