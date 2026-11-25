import 'package:flutter/material.dart';

import '../core/theme/tokens.dart';
import 'page_shell.dart';
import 'wp_fill_column.dart';

/// How the region under the head of a [WpEditorPane] uses its height.
enum WpEditorPaneBody {
  /// The editor fills the rest of the pane and its surface stretches to the
  /// status line at the bottom edge (Notes, static snippet, snippet detail).
  fill,

  /// Meta, editor and extras scroll together; the surface is as tall as its
  /// text (Recordings detail with its versions and annotations below, the
  /// interactive snippet form with its field list below).
  scroll,
}

/// The right-hand side of every editor: Recordings, Notes and Snippets
/// (#1498).
///
/// One component with fixed slots in a fixed order and fixed gaps, so the
/// three editors differ only in which slots they switch on:
///
/// 1. [head] — a `WpEditorHead` (title with priority, optional muted date
///    that gives way first, `WpHeadActions` ending with close). No leading
///    mark on any of the three.
/// 2. [notices] — full-width page notices and links; they bring their own
///    insets (`WpPageNoticeSlot` and friends).
/// 3. [meta] — an optional row of chips or banners above the editor.
/// 4. [editor] — always one `WpTextEditor`: tool row (format bar, which can
///    be on, off or disabled, and tags in its trailing slot), the writing
///    surface (the `passage`/`bare` card, read-only being a state of the same
///    surface) and the status line (words · reading time · save hint).
///    The editor draws the page inset itself, so its gutter (the note's
///    quick-note marks) can sit in that inset.
/// 5. [extras] — the optional area below (the recording's edit bar,
///    versions and annotations; the interactive snippet's field list).
/// 6. [footer] — at the bottom edge (the snippet editor's hint).
///
/// Where the window is too short for all slots (200 % text size, a low
/// window), the editor keeps its minimum and the whole pane scrolls instead
/// of overflowing (#1371, [WpFillColumn]).
///
/// The pane owns every inset between the slots: pages set no paddings of
/// their own. So head title, tool row, surface and status line start on the
/// same left edge, and close and surface end on the page toolbar's right
/// edge ([WpPageFrame.inset]), whichever editor is open.
class WpEditorPane extends StatelessWidget {
  const WpEditorPane({
    super.key,
    required this.head,
    this.notices = const [],
    this.meta,
    required this.editor,
    this.extras = const [],
    this.bodyMode = WpEditorPaneBody.fill,
    this.footer,
  });

  final Widget head;

  /// Full-width rows between head and content. They bring their own insets.
  final List<Widget> notices;

  /// A row above the editor, inside the page inset.
  final Widget? meta;

  /// The `WpTextEditor`. It carries the page inset itself.
  final Widget editor;

  /// Rows below the editor, inside the page inset, [extrasGap] apart.
  final List<Widget> extras;
  final WpEditorPaneBody bodyMode;

  /// At the bottom edge below the content (the snippet editor's hint).
  final Widget? footer;

  /// Step between head (or notices) and the first content row.
  static const double bodyTop = WpSpacing.xs;

  /// Room under the last row of a scrolling pane, so it never ends on the
  /// pane's edge.
  static const double bodyBottom = WpSpacing.xl;

  /// Gap between [meta] and the editor's tool row.
  static const double metaGap = WpSpacing.sm;

  /// Gap above each of the [extras].
  static const double extrasGap = WpSpacing.sm;

  /// Side insets of meta and extras: the page inset, the editor's own.
  static const EdgeInsets sideInset = EdgeInsets.symmetric(
    horizontal: WpPageFrame.inset,
  );

  /// Insets of the fixed [footer].
  static const EdgeInsets footerPadding = EdgeInsets.fromLTRB(
    WpPageFrame.inset,
    WpSpacing.sm,
    WpPageFrame.inset,
    WpSpacing.md,
  );

  /// Least height of the scrolling region of a [WpEditorPaneBody.scroll]
  /// pane at 100 % text size, scaled with the text (#1371).
  static const double minScrollBodyExtent = 160;

  @override
  Widget build(BuildContext context) {
    final fills = bodyMode == WpEditorPaneBody.fill;
    final metaRow = meta;
    final children = <Widget>[
      const SizedBox(height: bodyTop),
      if (metaRow != null) ...[
        Padding(padding: sideInset, child: metaRow),
        const SizedBox(height: metaGap),
      ],
      if (fills) WpFillSlot(probe: true, child: editor) else editor,
      for (final extra in extras) ...[
        const SizedBox(height: extrasGap),
        Padding(padding: sideInset, child: extra),
      ],
      if (!fills && footer == null) const SizedBox(height: bodyBottom),
    ];
    final Widget body = fills
        ? WpFillColumn(children: children)
        : SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: children,
            ),
          );
    final end = footer;
    final scaler = MediaQuery.textScalerOf(context);
    // Head, body and footer fill the pane like a column; where the window
    // is too short for them (200 % text size, a low window) the whole pane
    // scrolls instead of cutting off the editor's bottom (#1371). In a
    // window that fits there is nothing to scroll and nothing changes.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        primary: false,
        child: WpFillColumn(
          viewportExtent: constraints.maxHeight,
          minFillExtent: fills ? 0 : scaler.scale(minScrollBodyExtent),
          children: [
            head,
            ...notices,
            WpFillSlot(probe: fills, child: body),
            if (end != null) Padding(padding: footerPadding, child: end),
          ],
        ),
      ),
    );
  }
}
