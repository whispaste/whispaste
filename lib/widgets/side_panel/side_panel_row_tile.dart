import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../services/side_panel/side_panel_snapshot.dart';
import '../wp_focus_ring.dart';
import '../wp_list_tile_surface.dart';
import 'side_panel_focus_tooltip.dart';

/// One row of the side panel -- click-to-insert, a single-tone kind icon, a
/// single-line bold title with an optional muted subtitle, or a small
/// thumbnail for [SidePanelRowKind.image] rows. Rows carry no per-entry color:
/// the icon says what kind of row it is, not which entry it is. Mirrors the
/// hover-tracking pattern used by `HistoryEntryRow`, kept far simpler here:
/// the panel only ever renders pre-resolved strings, no derived-field
/// memoization needed.
class WpSidePanelRowTile extends StatefulWidget {
  const WpSidePanelRowTile({
    super.key,
    required this.row,
    required this.leadingIcon,
    required this.kindLabel,
    required this.onTap,
    this.onDragStart,
  });

  final SidePanelRow row;

  /// Localized section name ("Transcriptions", ...), spoken before the title
  /// so a screen reader says what kind of row it is.
  final String kindLabel;

  /// Glyph of the section this row belongs to -- it says what *kind* of
  /// thing the row is, in one tone for every row.
  final IconData leadingIcon;

  final VoidCallback onTap;

  /// Fires once a pointer that pressed down on this row has moved
  /// predominantly *horizontally* past Flutter's drag threshold (issue 11).
  /// Horizontal, not [GestureDetector.onPanStart]/any-direction: the panel
  /// sits flush against the screen's left edge, so dragging a row *out* of
  /// it and into another app's window is inherently a horizontal gesture,
  /// while a *vertical* drag on a row is what the surrounding row list's own
  /// `ListView` needs for scrolling. A `HorizontalDragGestureRecognizer`
  /// never enters gesture-arena competition with the list's
  /// `VerticalDragGestureRecognizer` (each only self-accepts once movement
  /// is dominantly its own axis), so this row starting a native drag can
  /// never also swallow the list's scroll gesture. Wiring both `onTap` and
  /// this on the same [GestureDetector] cannot cause a click to also fire a
  /// drag or vice versa either -- tap and horizontal-drag are separate
  /// recognizer families that the arena still resolves correctly against
  /// each other. Null keeps a row click-only (no native drag session
  /// started for it).
  final VoidCallback? onDragStart;

  @override
  State<WpSidePanelRowTile> createState() => _WpSidePanelRowTileState();
}

class _WpSidePanelRowTileState extends State<WpSidePanelRowTile> {
  bool _isHovered = false;

  /// Set during layout: whether the title or subtitle is cut off. Read by
  /// [WpSidePanelFocusTooltip] on focus changes.
  bool _labelTruncated = false;

  TextStyle get _titleStyle => TextStyle(
    color: WpColors.textPrimary,
    fontSize: WpTypography.body,
    fontWeight: FontWeight.w600,
  );
  TextStyle get _subtitleStyle =>
      TextStyle(color: WpColors.textMuted, fontSize: WpTypography.caption);

  bool _measureTruncated(BuildContext context, double maxWidth) {
    final scaler = MediaQuery.textScalerOf(context);
    final title = isOneLineTruncated(
      context,
      text: widget.row.title,
      style: _titleStyle,
      textScaler: scaler,
      maxWidth: maxWidth,
    );
    if (widget.row.subtitle.isEmpty) return title;
    return title ||
        isOneLineTruncated(
          context,
          text: widget.row.subtitle,
          style: _subtitleStyle,
          textScaler: scaler,
          maxWidth: maxWidth,
        );
  }

  final FocusNode _focusNode = FocusNode(debugLabel: 'WpSidePanelRowTile');

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final spoken = row.subtitle.isEmpty
        ? row.title
        : '${row.title}, ${row.subtitle}';
    return Semantics(
      identifier: 'side-panel-row-${row.id}',
      button: true,
      label: '${widget.kindLabel}, $spoken',
      child: ExcludeSemantics(
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: WpSidePanelFocusTooltip(
            message: widget.row.subtitle.isEmpty
                ? widget.row.title
                : '${widget.row.title}\n${widget.row.subtitle}',
            focusNode: _focusNode,
            isTruncated: () => _labelTruncated,
            showOnHover: false,
            child: WpFocusRing(
              focusNode: _focusNode,
              radius: WpRadius.lg,
              child: GestureDetector(
                onHorizontalDragStart: widget.onDragStart == null
                    ? null
                    : (_) => widget.onDragStart!(),
                child: InkWell(
                  onTap: widget.onTap,
                  focusNode: _focusNode,
                  borderRadius: WpRadius.borderLg,
                  // WpListTileSurface handles all hover/focus/tap styling.
                  // Suppress InkWell's default visual feedback.
                  focusColor: Colors.transparent,
                  hoverColor: Colors.transparent,
                  splashColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                  child: WpListTileSurface(
                    variant: WpListTileVariant.panel,
                    isHovered: _isHovered,
                    isFocused: _focusNode.hasFocus,
                    child: Row(
                      children: [
                        if (row.kind == SidePanelRowKind.image &&
                            row.imageBytes != null)
                          Padding(
                            padding: const EdgeInsets.only(right: WpSpacing.sm),
                            child: ClipRRect(
                              borderRadius: WpRadius.borderSm,
                              child: Image.memory(
                                Uint8List.fromList(row.imageBytes!),
                                width: _RowKindGlyph.size,
                                height: _RowKindGlyph.size,
                                fit: BoxFit.cover,
                                // The enclosing Semantics(label: ...) already names
                                // this row; the thumbnail itself carries no extra
                                // information for screen readers.
                                excludeFromSemantics: true,
                              ),
                            ),
                          )
                        else
                          Padding(
                            padding: const EdgeInsets.only(right: WpSpacing.sm),
                            child: _RowKindGlyph(icon: widget.leadingIcon),
                          ),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, box) {
                              _labelTruncated = _measureTruncated(
                                context,
                                box.maxWidth,
                              );
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    row.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: _titleStyle,
                                  ),
                                  if (row.subtitle.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      row.subtitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: _subtitleStyle,
                                    ),
                                  ],
                                ],
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The row's kind glyph: one neutral tone for every row, no per-entry tint.
/// Random or per-entry colors read as noise next to the text, so the kind
/// is carried by the icon alone.
class _RowKindGlyph extends StatelessWidget {
  const _RowKindGlyph({required this.icon});

  final IconData icon;

  static const double size = 28;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Icon(icon, size: WpIconSize.md, color: WpColors.textMuted),
      ),
    );
  }
}
