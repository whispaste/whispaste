import 'package:flutter/material.dart';

import '../core/theme/tokens.dart';
import 'page_shell.dart';

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
/// 6. [footer] — fixed at the bottom (the snippet editor's save actions).
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

  /// Fixed below the content (the snippet editor's hint and save actions).
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
      if (fills) Expanded(child: editor) else editor,
      for (final extra in extras) ...[
        const SizedBox(height: extrasGap),
        Padding(padding: sideInset, child: extra),
      ],
      if (!fills && footer == null) const SizedBox(height: bodyBottom),
    ];
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: fills ? MainAxisSize.max : MainAxisSize.min,
      children: children,
    );
    final end = footer;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        head,
        ...notices,
        Expanded(
          child: fills ? content : SingleChildScrollView(child: content),
        ),
        if (end != null) Padding(padding: footerPadding, child: end),
      ],
    );
  }
}
