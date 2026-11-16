import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import 'wp_row_action.dart';

// ---------------------------------------------------------------------------
// WpListItemContent — the one content layout for item rows (recordings,
// notes, snippets), placed inside a `WpListTileSurface` (#1498).
//
// The three lists used to build their rows three ways: a 42 px coloured
// disc on recordings, no glyph on notes, an accent glyph on snippets;
// actions on the title line in two lists and in a column beside the whole
// body in the third; a meta line that wrapped in one list and not in the
// others. Moving between the lists, the eye had to relearn what a row is.
// Now one layout holds them all and only the type glyph says which kind of
// item a row is.
//
//   [slot] [glyph]  Title ······························ [actions]
//                   Preview (only when it adds something to the title)
//                   Meta · one line · ellipsized
//                   [footer: tags, badges]
//
// * One accessible name per row (#1498): the preview is never read out as
//   rendered. A Text exposes its whole string, not the visible two lines, so
//   a long recording was announced as its title (the opening of the text,
//   ellipsized) followed by the full text. The row now says the title, at
//   most a short excerpt ([previewSemanticsLabel], built with
//   [WpListItemContent.spokenPreview]) and the meta line.
// * Type glyph: one size for every kind (`WpIconSize.sm`), muted, no circle.
//   It is a kind marker, not decoration; colour stays out of it so the row's
//   only coloured ink is the state it carries (favourite star, selection).
// * Actions sit on the title line, never beside the whole body: preview and
//   meta keep the full row width. They are the dense variant everywhere, so
//   revealing them never makes the title line taller than its 28 px box
//   (see `wp_row_action.dart` for the dense exception). The shared set is
//   Copy, Star, Delete in that order, right-aligned ([WpListItemActions]),
//   revealed by hover, the keyboard cursor or the row being the open one.
//   Copy carries one name in every list, `historyCopyText` ("Copy text"),
//   because all three copy the item's text. Star is [WpFavouriteStar] in
//   every list: one glyph pair, one 28 px box, one name ("Add to
//   favorites" / "Remove from favorites").
//   Anything else (Duplicate, setting the quick-note mark) lives in the
//   row's context menu and as a screen-reader custom action, so no row
//   shows more than three revealed actions. While the actions are hidden a
//   favourite shows the resting [WpListItemStarMark] after the title.
// * Preview: callers drop it when it would only repeat the title
//   ([previewDiffers]), so a short recording does not print its text twice.
// * Meta: exactly one line ([WpListItemMeta]), ellipsized at the end. The
//   leading facts (time) survive a narrow panel; the tail is what gives way.
//   Built from segments, a missing fact (unknown target app, no language)
//   is dropped instead of leaving "18:08 ·  · 0s".
// * Slots for the functional differences: [leading] (multi-select checkbox),
//   [titleTrailing] (status badges after the title), [footer] (tag chips,
//   error state).
// * Title priority: [titleTrailing] shows only while the title keeps
//   [WpListItemContent.titleMinShare] of the title line; marks that would
//   push it below drop out, the last one first.
// ---------------------------------------------------------------------------

/// Shared content of a list item row. See the library comment.
class WpListItemContent extends StatelessWidget {
  const WpListItemContent({
    super.key,
    required this.typeIcon,
    required this.title,
    this.typeIconColor,
    this.leading,
    this.titleTrailing = const [],
    this.actions,
    this.preview,
    this.previewSemanticsLabel,
    this.meta,
    this.footer,
  });

  /// The kind glyph (recording, note, snippet). Same size for every kind.
  final IconData typeIcon;

  /// Defaults to `WpColors.textMuted`. Callers dim it further for inert rows
  /// (trash); they do not colour it by kind.
  final Color? typeIconColor;

  /// Optional slot in front of the glyph, e.g. the multi-select checkbox.
  final Widget? leading;

  /// The one-line title, already ellipsized by the caller.
  final Widget title;

  /// Small badges right after the title (draft, interactive, status).
  /// They give way to the title: see [titleMinShare].
  final List<Widget> titleTrailing;

  /// Share of the title line (without the actions) the title keeps before
  /// [titleTrailing] gives way, from the last mark backwards. The same rule
  /// as the meta of `WpEditorHead`, so a narrow list never shows
  /// "E-Mail-Sig… [Interactive]".
  static const double titleMinShare = 0.6;

  /// Trailing group on the title line, typically a dense `WpRowActions`.
  final Widget? actions;

  /// Body excerpt; pass null when [previewDiffers] says it repeats the title.
  /// Visual only: its own semantics are always excluded, see
  /// [previewSemanticsLabel].
  final Widget? preview;

  /// What a screen reader hears for [preview], normally
  /// [spokenPreview]`(title, text)`. Null keeps the preview silent.
  final String? previewSemanticsLabel;

  /// The single meta line, typically a [WpListItemMeta].
  final Widget? meta;

  /// Tag chips, error state or anything else below the meta line.
  final Widget? footer;

  /// Height of the title line: the dense action box, reserved whether or not
  /// actions are showing, so glyph, checkbox and title share one centre line.
  static double get titleLineHeight => WpRowAction.extentFor(dense: true);

  /// Whether [preview] adds anything to [title]. Compares case-insensitively
  /// with whitespace collapsed and trailing punctuation dropped, because a
  /// generated title is usually the opening of the text it summarizes.
  static bool previewDiffers(String title, String preview) {
    final p = _norm(preview);
    if (p.isEmpty) return false;
    return p != _norm(title);
  }

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'[\s.…!?,;:]+$'), '')
      .trim();

  /// Longest preview excerpt a screen reader hears, in characters.
  static const int spokenPreviewLimit = 120;

  /// The spoken form of a preview: null when [text] adds nothing to [title]
  /// for the ear (the same text, or a generated title that is the text's own
  /// opening), otherwise [text] with whitespace collapsed and cut at a word
  /// boundary to [spokenPreviewLimit] characters plus "…".
  static String? spokenPreview(String title, String text) {
    if (!previewDiffers(title, text)) return null;
    final opening = _norm(title);
    final collapsed = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (opening.isNotEmpty && collapsed.toLowerCase().startsWith(opening)) {
      return null;
    }
    if (collapsed.length <= spokenPreviewLimit) return collapsed;
    final cut = collapsed.substring(0, spokenPreviewLimit);
    final space = cut.lastIndexOf(' ');
    final head = space > spokenPreviewLimit ~/ 2
        ? cut.substring(0, space)
        : cut;
    return '${head.trimRight()}…';
  }

  @override
  Widget build(BuildContext context) {
    final lineHeight = titleLineHeight;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (leading case final leading?) ...[
          SizedBox(
            height: lineHeight,
            child: Center(child: leading),
          ),
          const SizedBox(width: WpSpacing.xs),
        ],
        SizedBox(
          height: lineHeight,
          child: Center(
            child: WpListItemTypeGlyph(icon: typeIcon, color: typeIconColor),
          ),
        ),
        const SizedBox(width: WpSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(minHeight: lineHeight),
                child: Row(
                  children: [
                    // Title and badges share one Expanded so the actions
                    // always end at the row edge. A Flexible title next to a
                    // Spacer splits the free space in half, which left the
                    // cluster mid-row under a short title.
                    //
                    // The title has priority (as in `WpEditorHead`): the
                    // trailing marks show while the title keeps
                    // [titleMinShare] of that space and drop out from the end
                    // instead of cutting the title short.
                    Expanded(
                      child: titleTrailing.isEmpty
                          ? Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: title,
                            )
                          : _TitleWithTrailing(
                              title: title,
                              trailing: titleTrailing,
                            ),
                    ),
                    if (actions case final actions?) ...[
                      const SizedBox(width: WpSpacing.xs),
                      actions,
                    ],
                  ],
                ),
              ),
              if (preview case final preview?)
                previewSemanticsLabel == null
                    ? ExcludeSemantics(child: preview)
                    : Semantics(
                        label: previewSemanticsLabel,
                        excludeSemantics: true,
                        child: preview,
                      ),
              if (meta case final meta?) ...[
                const SizedBox(height: WpSpacing.xxs),
                meta,
              ],
              if (footer case final footer?) ...[
                const SizedBox(height: WpSpacing.xxs),
                footer,
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The type glyph of an item (recording, note, snippet): `WpIconSize.sm`,
/// `WpColors.textMuted`, no circle, no colour by kind. The list row, the
/// recordings card and the recording detail head all draw it through this
/// widget, so a recording wears one mark wherever it appears (#1498).
/// Decorative: the kind is already in the surrounding label.
class WpListItemTypeGlyph extends StatelessWidget {
  const WpListItemTypeGlyph({super.key, required this.icon, this.color});

  final IconData icon;

  /// Defaults to `WpColors.textMuted`; callers only dim it for inert items.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Icon(
        icon,
        size: WpIconSize.sm,
        color: color ?? WpColors.textMuted,
      ),
    );
  }
}

/// The revealed action cluster of an item row, the one set and the one order
/// for recordings, notes and snippets (#1498): Copy, Star, Delete. Trash rows
/// use [WpListItemActions.trash]: Copy, Restore, Delete forever. Absent
/// actions are simply left out, the order of the rest never changes.
///
/// Wraps a dense `WpRowActions`, so the cluster sits right-aligned at the end
/// of the title line, is unmounted while hidden and is one tab stop per row.
class WpListItemActions extends StatelessWidget {
  const WpListItemActions({
    super.key,
    required this.visible,
    this.copy,
    this.star,
    this.delete,
  }) : restore = null;

  const WpListItemActions.trash({
    super.key,
    required this.visible,
    this.copy,
    required Widget this.restore,
    required Widget this.delete,
  }) : star = null;

  /// Hover, keyboard focus or the row being the open one.
  final bool visible;
  final Widget? copy;
  final Widget? star;
  final Widget? restore;
  final Widget? delete;

  @override
  Widget build(BuildContext context) {
    return WpRowActions(
      visible: visible,
      dense: true,
      children: [?copy, ?star, ?restore, ?delete],
    );
  }
}

/// The resting favourite mark: a small solid star after the title while the
/// item is a favourite and its actions are hidden. Not a control; the
/// operable star is part of [WpListItemActions]. With [semanticsLabel] the
/// state is announced, without it the mark is decorative.
class WpListItemStarMark extends StatelessWidget {
  const WpListItemStarMark({super.key, this.semanticsLabel});

  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    const icon = FaIcon(
      FontAwesomeIcons.solidStar,
      size: WpIconSize.xs,
      color: WpSharedColors.pinnedAccent,
    );
    final label = semanticsLabel;
    if (label == null) return const ExcludeSemantics(child: icon);
    return Semantics(label: label, excludeSemantics: true, child: icon);
  }
}

/// The single meta line of a [WpListItemContent]: one text run, one line,
/// ellipsized at the end. Icons go in as `WidgetSpan`s so the line still
/// ellipsizes as a whole.
class WpListItemMeta extends StatelessWidget {
  const WpListItemMeta({super.key, required this.spans, this.color});

  /// Builds the line from facts ([join]): missing or blank segments are
  /// dropped, so the line never shows an empty slot between two separators.
  WpListItemMeta.segments({
    super.key,
    required Iterable<List<InlineSpan>?> segments,
    this.color,
  }) : spans = join(segments);

  final List<InlineSpan> spans;

  /// Base text colour; defaults to `WpColors.textMuted`.
  final Color? color;

  /// Separator between two facts, in the line's own style.
  static const String separator = ' · ';

  /// Joins [segments] with [separator], skipping null segments, empty ones
  /// and those whose text spans are all blank (and which carry no widget).
  static List<InlineSpan> join(Iterable<List<InlineSpan>?> segments) {
    final out = <InlineSpan>[];
    for (final segment in segments) {
      if (segment == null || !_hasContent(segment)) continue;
      if (out.isNotEmpty) out.add(const TextSpan(text: separator));
      out.addAll(segment);
    }
    return out;
  }

  static bool _hasContent(List<InlineSpan> segment) {
    for (final span in segment) {
      if (span is WidgetSpan) return true;
      if (span is TextSpan) {
        if ((span.text ?? '').trim().isNotEmpty) return true;
        if (span.children case final children? when _hasContent(children)) {
          return true;
        }
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(children: spans),
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: WpTypography.caption,
        color: color ?? WpColors.textMuted,
      ),
    );
  }
}

/// The title followed by its trailing marks, with the title's priority
/// applied ([WpListItemContent.titleMinShare]). A mark that does not fit is
/// neither painted, hit-tested nor announced.
class _TitleWithTrailing extends MultiChildRenderObjectWidget {
  _TitleWithTrailing({required Widget title, required List<Widget> trailing})
    : super(children: [title, ...trailing]);

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderTitleWithTrailing(Directionality.of(context));

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderTitleWithTrailing renderObject,
  ) {
    renderObject.textDirection = Directionality.of(context);
  }
}

class _TitleTrailingParentData extends ContainerBoxParentData<RenderBox> {
  bool shown = true;
}

class _RenderTitleWithTrailing extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _TitleTrailingParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _TitleTrailingParentData> {
  _RenderTitleWithTrailing(this._textDirection);

  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (value == _textDirection) return;
    _textDirection = value;
    markNeedsLayout();
  }

  static const double _gap = WpSpacing.xs;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _TitleTrailingParentData) {
      child.parentData = _TitleTrailingParentData();
    }
  }

  _TitleTrailingParentData _data(RenderBox child) =>
      child.parentData! as _TitleTrailingParentData;

  @override
  void performLayout() {
    final title = firstChild!;
    final maxWidth = constraints.maxWidth;
    final loose = BoxConstraints(maxWidth: maxWidth);
    // Trailing marks first: their widths decide how many the title allows.
    final budget = maxWidth.isFinite
        ? maxWidth * (1 - WpListItemContent.titleMinShare)
        : double.infinity;
    var used = 0.0;
    var dropping = false;
    var height = 0.0;
    for (var mark = childAfter(title); mark != null; mark = childAfter(mark)) {
      mark.layout(loose, parentUsesSize: true);
      final width = used + _gap + mark.size.width;
      final shown = !dropping && width <= budget;
      _data(mark).shown = shown;
      if (shown) {
        used = width;
        height = height < mark.size.height ? mark.size.height : height;
      } else {
        dropping = true;
      }
    }
    title.layout(
      BoxConstraints(
        maxWidth: maxWidth.isFinite ? maxWidth - used : double.infinity,
      ),
      parentUsesSize: true,
    );
    _data(title).shown = true;
    if (title.size.height > height) height = title.size.height;
    height = constraints.constrainHeight(height);
    final contentWidth = title.size.width + used;
    size = constraints.constrain(Size(contentWidth, height));
    final rtl = _textDirection == TextDirection.rtl;
    var x = 0.0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final data = _data(child);
      if (!data.shown) continue;
      if (child != title) x += _gap;
      final dy = (height - child.size.height) / 2;
      final dx = rtl ? size.width - x - child.size.width : x;
      data.offset = Offset(dx, dy);
      x += child.size.width;
    }
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      firstChild?.getMinIntrinsicHeight(width) ?? 0;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      firstChild?.getMaxIntrinsicHeight(width) ?? 0;

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    var height = 0.0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final h = child
          .getDryLayout(BoxConstraints(maxWidth: constraints.maxWidth))
          .height;
      if (h > height) height = h;
    }
    return constraints.constrain(Size(constraints.maxWidth, height));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final data = _data(child);
      if (data.shown) context.paintChild(child, offset + data.offset);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    for (var child = lastChild; child != null; child = childBefore(child)) {
      final data = _data(child);
      if (!data.shown) continue;
      final hit = result.addWithPaintOffset(
        offset: data.offset,
        position: position,
        hitTest: (result, transformed) =>
            child!.hitTest(result, position: transformed),
      );
      if (hit) return true;
    }
    return false;
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    for (var child = firstChild; child != null; child = childAfter(child)) {
      if (_data(child).shown) visitor(child);
    }
  }
}
