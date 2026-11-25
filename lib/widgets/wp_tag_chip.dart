/// WpTagChip — the one tag chip of the app (#1757).
///
/// Recordings, notes and the tag editor each drew their own chip: an
/// accent-tinted pill in the editor, an accent mini tag on a note, a
/// category-hued mini tag on a recording. The same tag looked three ways
/// depending on where it stood. Now every tag is painted in its own category
/// hue (`categorySlotForTag`): *The Tint Ladder Rule*'s 12 % fill and 30 %
/// outline, `#name` in `textSecondary`, small corners. The hue never carries
/// the label (eight hues behind small text would be eight contrast problems);
/// the name already says which tag it is.
///
/// Two densities, one look:
/// - [WpTagChip.new] — the compact chip of a list row's footer (caption text,
///   hugs its text). Read-only, or a button when [onTap] is set (filters the
///   list by that tag).
/// - [WpTagChip.editable] — the chip inside the tag editor (body text, room
///   for the remove glyph), with an optional remove control.
///
/// [WpTagChipRow] is the list-row footer: at most three chips and a "+N"
/// count.
library;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/l10n/generated/app_localizations.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import 'wp_focus_ring.dart';

class WpTagChip extends StatefulWidget {
  /// The compact chip of a list row. [onTap] makes it a button.
  const WpTagChip({super.key, required this.name, this.onTap})
    : onRemove = null,
      editable = false;

  /// The chip inside the tag editor. [onRemove] adds the remove control;
  /// null shows the tag read-only at the same size.
  const WpTagChip.editable({super.key, required this.name, this.onRemove})
    : onTap = null,
      editable = true;

  /// Tag name without the `#`, which the chip adds.
  final String name;

  /// Tap on a compact chip.
  final VoidCallback? onTap;

  /// Remove control of an editable chip.
  final VoidCallback? onRemove;

  final bool editable;

  @override
  State<WpTagChip> createState() => _WpTagChipState();
}

class _WpTagChipState extends State<WpTagChip> {
  bool _hovered = false;
  FocusNode? _focusNode;

  FocusNode get _node => _focusNode ??= FocusNode(
    debugLabel: widget.editable ? 'TagChipRemove' : 'EntryTagChip',
  );

  @override
  void dispose() {
    _focusNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slot = categorySlotForTag(widget.name);
    final ink = WpColors.textSecondary;
    final label = Text(
      '#${widget.name}',
      style: TextStyle(
        fontSize: widget.editable ? WpTypography.body : WpTypography.caption,
        color: ink,
        fontWeight: FontWeight.w500,
      ),
    );
    final decoration = BoxDecoration(
      color: slot.chipFill(),
      border: Border.all(color: slot.chipBorder()),
      borderRadius: WpRadius.borderSm,
    );

    if (!widget.editable) {
      final chip = Container(
        // Vertical 1 stays off-scale on purpose: the mini tag hugs its micro
        // text; xxs would double the chip height.
        padding: const EdgeInsets.symmetric(
          horizontal: WpSpacing.xxs,
          vertical: 1,
        ),
        decoration: decoration,
        child: label,
      );
      if (widget.onTap == null) return chip;
      return Semantics(
        button: true,
        label: '#${widget.name}',
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: WpFocusRing(
            focusNode: _node,
            radius: WpRadius.sm,
            child: InkWell(
              onTap: widget.onTap,
              focusNode: _node,
              borderRadius: WpRadius.borderSm,
              // WpFocusRing owns all focus visuals — suppress InkWell's own.
              focusColor: Colors.transparent,
              hoverColor: Colors.transparent,
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
              child: chip,
            ),
          ),
        ),
      );
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        padding: EdgeInsets.only(
          left: WpSpacing.sm,
          right: widget.onRemove == null ? WpSpacing.sm : WpSpacing.xxs,
          top: WpSpacing.xxs + 2,
          bottom: WpSpacing.xxs + 2,
        ),
        decoration: decoration,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            label,
            if (widget.onRemove != null) ...[
              const SizedBox(width: WpSpacing.xxs),
              Semantics(
                button: true,
                label: L10n.of(context).tagRemoveSemanticsLabel(widget.name),
                child: WpFocusRing(
                  focusNode: _node,
                  radius: WpRadius.sm,
                  child: InkWell(
                    onTap: widget.onRemove,
                    focusNode: _node,
                    borderRadius: WpRadius.borderSm,
                    focusColor: Colors.transparent,
                    hoverColor: Colors.transparent,
                    splashColor: Colors.transparent,
                    highlightColor: Colors.transparent,
                    child: Padding(
                      // 2px pad enlarges the remove icon's tap area without
                      // inflating the chip height.
                      padding: const EdgeInsets.all(2),
                      child: AnimatedOpacity(
                        // 0.6 at rest keeps the only visible delete affordance
                        // readable on touch and keyboard (UIA-CMP-04).
                        opacity: _hovered ? 0.9 : 0.6,
                        duration: WpMotion.durationFor(
                          context,
                          _hovered ? WpMotion.hoverIn : WpMotion.hoverOut,
                        ),
                        child: Icon(
                          LucideIcons.x,
                          size: WpIconSize.xs,
                          color: ink,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Footer of a list row: up to three [WpTagChip]s and a "+N" for the rest.
class WpTagChipRow extends StatelessWidget {
  const WpTagChipRow({super.key, required this.names, this.onTagTap});

  final List<String> names;

  /// Makes every chip a button that hands its tag name back.
  final void Function(String name)? onTagTap;

  static const int _visible = 3;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 2,
      children: [
        for (final name in names.take(_visible))
          WpTagChip(
            name: name,
            onTap: onTagTap == null ? null : () => onTagTap!(name),
          ),
        if (names.length > _visible)
          Text(
            '+${names.length - _visible}',
            style: TextStyle(
              fontSize: WpTypography.caption,
              color: WpColors.textMuted,
            ),
          ),
      ],
    );
  }
}
