import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import 'page_shell.dart';
import 'wp_icon_button.dart';

/// How a head fits its action strip when the row runs short.
enum WpEditorHeadFit {
  /// The strip scrolls sideways inside at most [WpEditorHead.actionsShare]
  /// of the row, close kept in view (Recordings, Snippets).
  scroll,

  /// The strip scales down instead; the caller already budgets which actions
  /// fit (Notes, which moves the rest into its menu).
  scale,
}

/// The head of every editor panel — Recordings detail, note, snippet detail
/// and snippet editor (#1498).
///
/// One band in all four: the same insets ([padding]), one row of at least
/// [rowExtent] with the title on the left in the heading style and the
/// [WpHeadActions] strip on the right, ending on the page inset where the
/// editor surface below ends. Title fields inside it use
/// `WpTextFieldVariant.heading`: unfilled and edgeless at rest, the accent
/// contour only while focused. So the text below starts at the same height
/// in every editor, whichever one is open.
class WpEditorHead extends StatelessWidget {
  const WpEditorHead({
    super.key,
    this.leading,
    required this.title,
    this.meta,
    required this.actions,
    this.actionsFit = WpEditorHeadFit.scroll,
    this.below,
  });

  /// A mark before the title (the note's quick-note bolt, the recording's
  /// source glyph).
  final Widget? leading;

  /// Takes all the width the actions leave.
  final Widget title;

  /// Short muted text after the title (the recording's time).
  ///
  /// The title has priority: the meta shows only while it fits whole and
  /// the title still keeps [titleMinShare] of the row. In a narrower head it
  /// drops out instead of cutting both; the selected list row beside the
  /// detail shows the same time (#1498).
  final String? meta;

  /// Usually a [WpHeadActions]; may be preceded by a control of the editor
  /// (the snippet's kind choice) inside the same widget.
  final Widget actions;
  final WpEditorHeadFit actionsFit;

  /// A second row under the head, only where the width forces one (the
  /// snippet's kind choice in a narrow pane).
  final Widget? below;

  /// How far the close glyph sits inside its square slot: the slot is wider
  /// than the icon, so without this the X would end short of the page edge.
  static const double closeOverhang =
      (WpHeadActions.slot - WpIconSize.smMd) / 2;

  /// Page inset left; on the right the inset minus [closeOverhang], so the
  /// close X ends on the same line as the page toolbar on all three editors
  /// (#1498). The compact buttons' breathing room above and below.
  static const EdgeInsets padding = EdgeInsets.fromLTRB(
    WpPageFrame.inset,
    WpSpacing.xs,
    WpPageFrame.inset - closeOverhang,
    WpSpacing.xxs,
  );

  /// Minimum height of the head row: the heading-style title field with its
  /// focus contour, so editing the title never changes the band's height.
  static const double rowExtent = WpSpacing.xxl + WpSpacing.xs;

  /// Most of the row the action strip may take in [WpEditorHeadFit.scroll].
  static const double actionsShare = 0.6;

  /// Share of the title row the title keeps before [meta] gives way.
  static const double titleMinShare = 0.6;

  static const TextStyle _metaStyle = TextStyle(fontSize: WpTypography.small);

  Widget _titleWithMeta() {
    final text = meta;
    if (text == null) return title;
    return LayoutBuilder(
      builder: (context, box) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: _metaStyle),
          maxLines: 1,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        final metaWidth = painter.width + WpSpacing.xs;
        painter.dispose();
        final fits =
            !box.hasBoundedWidth ||
            box.maxWidth - metaWidth >= box.maxWidth * titleMinShare;
        if (!fits) return title;
        return Row(
          children: [
            Expanded(child: title),
            const SizedBox(width: WpSpacing.xs),
            Text(
              text,
              maxLines: 1,
              softWrap: false,
              style: _metaStyle.copyWith(color: WpColors.textMuted),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final strip = switch (actionsFit) {
            // Scrolls instead of overflowing at 800 px and text scale 1.3;
            // `reverse` keeps close in view. Shrink-wrapped and capped
            // rather than [Flexible]: a loose flex child split the free
            // space with the title and left close short of the page edge.
            WpEditorHeadFit.scroll => ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: constraints.hasBoundedWidth
                    ? constraints.maxWidth * actionsShare
                    : double.infinity,
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                child: actions,
              ),
            ),
            // The split view renders the panel down to 280 dp during its
            // open/close animation; there the strip scales instead of
            // overflowing (FLUTTER_WHISPASTE-64).
            WpEditorHeadFit.scale => Flexible(
              flex: 0,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerEnd,
                child: actions,
              ),
            ),
          };
          final row = ConstrainedBox(
            constraints: const BoxConstraints(minHeight: rowExtent),
            child: Row(
              children: [
                ?leading,
                Expanded(child: _titleWithMeta()),
                const SizedBox(width: WpSpacing.xs),
                strip,
              ],
            ),
          );
          final extra = below;
          if (extra == null) return row;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              row,
              const SizedBox(height: WpSpacing.xs),
              // The head's right inset is short by [closeOverhang] for the
              // close glyph; the second row ends on the page inset instead.
              Padding(
                padding: const EdgeInsets.only(right: closeOverhang),
                child: extra,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The action strip in the head of an editor panel (Recordings, Notes,
/// Snippets; #1498).
///
/// Every action sits in a slot of the same size ([slot]) with the same gap
/// ([gap]) to its neighbours, so the strip reads as one even row no matter
/// which button sits in a slot. Order is the caller's job and follows one
/// rule in all three editors: domain actions first, then the "…" menu, then
/// close on the far right.
class WpHeadActions extends StatelessWidget {
  const WpHeadActions({
    super.key,
    required this.actions,
    this.menu,
    required this.close,
  });

  /// Domain actions, most important first (copy, voice, star, …).
  final List<Widget> actions;

  /// The "…" menu, usually a [WpHeadMenuButton]; directly before [close].
  final Widget? menu;

  /// The close button, always the last slot.
  final Widget close;

  /// Side of one slot: the compact icon button.
  static const double slot = WpIconButton.compactExtent;

  /// Gap between two slots.
  static const double gap = WpSpacing.xxs;

  /// Width of a strip with [count] slots.
  static double widthFor(int count) =>
      count <= 0 ? 0 : count * slot + (count - 1) * gap;

  @override
  Widget build(BuildContext context) {
    final children = [...actions, ?menu, close];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: gap),
          SizedBox.square(
            dimension: slot,
            child: Center(child: children[i]),
          ),
        ],
      ],
    );
  }
}

/// The "…" trigger of an editor head: a compact square with the same glyph,
/// size and menu surface in every editor, so the three menus look and behave
/// alike (#1498).
class WpHeadMenuButton<T> extends StatelessWidget {
  const WpHeadMenuButton({
    super.key,
    required this.testId,
    required this.tooltip,
    required this.itemBuilder,
    required this.onSelected,
  });

  /// Semantics identifier of the trigger (`<screen>-more` or similar).
  final String testId;
  final String tooltip;
  final PopupMenuItemBuilder<T> itemBuilder;
  final PopupMenuItemSelected<T> onSelected;

  @override
  Widget build(BuildContext context) {
    // One node: the identifier merges into the menu button's own node, which
    // already carries `button` and the tooltip as its name. A separate
    // `Semantics(button: true)` here produced a second, nameless button with
    // the same rect (#1498).
    return MergeSemantics(
      child: Semantics(
        identifier: testId,
        child: SizedBox.square(
          dimension: WpHeadActions.slot,
          // Menu exception (#1757): WpHeadActions is the design system's
          // editor-head menu slot with its own fixed square geometry;
          // allowlisted in wp_raw_component_guard_test.
          child: PopupMenuButton<T>(
            tooltip: tooltip,
            padding: EdgeInsets.zero,
            iconSize: WpIconSize.smMd,
            icon: Icon(LucideIcons.ellipsis, color: WpColors.textSecondary),
            style: IconButton.styleFrom(
              fixedSize: const Size.square(WpHeadActions.slot),
              minimumSize: const Size.square(WpHeadActions.slot),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(WpRadius.md),
              ),
            ),
            // A popup menu floats over arbitrary content — pre-composited card
            // material, see `WpColors.floatingSurface`.
            color: WpColors.floatingSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(WpRadius.md),
            ),
            itemBuilder: itemBuilder,
            onSelected: onSelected,
          ),
        ),
      ),
    );
  }
}

/// One row of an editor "…" menu: icon and label, error colour when the
/// action destroys something. Every item of every head menu uses it.
class WpMenuRow extends StatelessWidget {
  const WpMenuRow({
    super.key,
    required this.icon,
    required this.label,
    this.isDestructive = false,
  });

  final IconData icon;
  final String label;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final color = isDestructive ? WpColors.error : WpColors.textPrimary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: WpIconSize.sm, color: color),
        const SizedBox(width: WpSpacing.sm),
        Flexible(
          child: Text(
            label,
            style: TextStyle(fontSize: WpTypography.body, color: color),
          ),
        ),
      ],
    );
  }
}
