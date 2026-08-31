import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../services/side_panel/side_panel_snapshot.dart';
import '../wp_list_tile_surface.dart';

/// One row of the side panel -- click-to-insert, a leading glyph disc in the
/// main window's avatar material, single-line bold title with an optional
/// muted subtitle, or a small thumbnail for [SidePanelRowKind.image] rows.
/// Mirrors the hover-tracking pattern used by `HistoryEntryRow`, kept far
/// simpler here: the panel only ever renders pre-resolved strings, no
/// derived-field memoization needed.
class WpSidePanelRowTile extends StatefulWidget {
  const WpSidePanelRowTile({
    super.key,
    required this.row,
    required this.leadingIcon,
    required this.onTap,
    this.onDragStart,
  });

  final SidePanelRow row;

  /// Glyph of the section this row belongs to -- the disc says what *kind*
  /// of thing the row is, the way the main window's entry avatar does.
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

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    return Semantics(
      button: true,
      label: row.subtitle.isEmpty ? row.title : '${row.title}, ${row.subtitle}',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          onHorizontalDragStart: widget.onDragStart == null
              ? null
              : (_) => widget.onDragStart!(),
          child: WpListTileSurface(
            variant: WpListTileVariant.panel,
            isHovered: _isHovered,
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
                        width: _RowGlyphDisc.size,
                        height: _RowGlyphDisc.size,
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
                    child: _RowGlyphDisc(
                      icon: widget.leadingIcon,
                      colorSlot: row.colorSlot,
                    ),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        row.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: WpColors.textPrimary,
                          fontSize: WpTypography.body,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (row.subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          row.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: WpColors.textMuted,
                            fontSize: WpTypography.caption,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Scaled-down sibling of the main window's `HistoryEntryAvatar`: the same
/// disc material ([WpAvatarTint.dark] gradient, hue-tinted rim, lifted
/// glyph), sized for a dense quick-paste row.
///
/// Tinted from [colorSlot] when the row has one -- an index into
/// `WpCategorySlot.categories`, the same persisted slot the main window's
/// `HistoryEntryAvatar` reads, so a transcription's disc here matches the
/// same entry's avatar there. Falls back to [WpCategorySlot.neutral] for row
/// kinds with no persisted slot (snippets, clipboard history) and for any
/// out-of-range value, rather than hashing one: a hashed hue here would
/// disagree with the color the same entry wears in the main window.
class _RowGlyphDisc extends StatelessWidget {
  const _RowGlyphDisc({required this.icon, this.colorSlot});

  final IconData icon;
  final int? colorSlot;

  static const double size = 28;

  @override
  Widget build(BuildContext context) {
    const tint = WpAvatarTint.dark;
    final slot = colorSlot;
    const categories = WpCategorySlot.categories;
    final resolvedSlot = (slot != null && slot >= 0 && slot < categories.length)
        ? categories[slot]
        : WpCategorySlot.neutral;
    final base = resolvedSlot.color();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: tint.discGradient(base),
        shape: BoxShape.circle,
        border: Border.all(color: tint.edge(base), width: 1),
      ),
      child: Icon(
        icon,
        size: (size * 0.44).roundToDouble(),
        color: tint.glyph(base),
      ),
    );
  }
}
