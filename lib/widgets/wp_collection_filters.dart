/// Filter parts of the collection toolbar (`internal-notes`, #1201).
///
/// One filter button opens a popover with the page's [WpFilterSection]s; what
/// is active shows as compact, removable [WpActiveFilter] marks on the same
/// row as the search. The pages only decide which filters they offer.
library;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/l10n/generated/app_localizations.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import 'wp_focus_ring.dart';
import 'wp_icon_button.dart';

/// One titled group in the filter popover, e.g. "Show", "Period", "Tags".
class WpFilterSection {
  const WpFilterSection({
    required this.id,
    required this.label,
    required this.children,
  });

  /// Stable part of the landmark id `<screen>-filter-section-<id>`.
  final String id;

  /// Visible group title.
  final String label;

  /// The group's choices, normally `WpFilterChip`s. They wrap onto more lines
  /// inside the popover, so nothing scrolls sideways there.
  final List<Widget> children;
}

/// One active filter, shown as a mark next to the search.
class WpActiveFilter {
  const WpActiveFilter({
    required this.id,
    required this.label,
    required this.onRemove,
  });

  /// Stable part of the id `<screen>-filter-mark-<id>`.
  final String id;

  /// What the filter does, short ("Trash", "#work", "Last 7 days").
  final String label;

  /// Turns the filter off.
  final VoidCallback onRemove;
}

/// The filter button with its popover. The badge counts the active filters,
/// so a filter hidden in the popover is never invisible.
class WpFilterMenuButton extends StatefulWidget {
  const WpFilterMenuButton({
    super.key,
    required this.screenId,
    required this.sections,
    required this.activeCount,
  });

  final String screenId;
  final List<WpFilterSection> sections;
  final int activeCount;

  /// Width of the popover panel.
  static const double panelWidth = 340;

  @override
  State<WpFilterMenuButton> createState() => _WpFilterMenuButtonState();
}

class _WpFilterMenuButtonState extends State<WpFilterMenuButton> {
  final MenuController _controller = MenuController();

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final count = widget.activeCount;
    final id = widget.screenId;
    return MenuAnchor(
      controller: _controller,
      alignmentOffset: const Offset(0, WpSpacing.xxs),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(WpColors.floatingSurface),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: WpRadius.borderMd),
        ),
      ),
      menuChildren: [
        Semantics(
          identifier: '$id-filter-panel',
          container: true,
          explicitChildNodes: true,
          child: SizedBox(
            width: WpFilterMenuButton.panelWidth,
            child: Padding(
              padding: const EdgeInsets.all(WpSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < widget.sections.length; i++) ...[
                    if (i > 0) const SizedBox(height: WpSpacing.sm),
                    _Section(screenId: id, section: widget.sections[i]),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
      builder: (context, controller, _) => Stack(
        clipBehavior: Clip.none,
        children: [
          WpIconButton(
            icon: LucideIcons.listFilter,
            tooltip: l10n.collectionFilterMenu,
            semanticsLabel: count == 0
                ? l10n.collectionFilterMenu
                : l10n.collectionFilterMenuActive(count),
            testId: '$id-filter-menu',
            color: count > 0 ? WpColors.accent : null,
            onPressed: () =>
                controller.isOpen ? controller.close() : controller.open(),
          ),
          if (count > 0)
            PositionedDirectional(
              top: -WpSpacing.xxs,
              end: -WpSpacing.xxs,
              child: ExcludeSemantics(
                child: Container(
                  constraints: const BoxConstraints(minWidth: 16),
                  padding: const EdgeInsets.symmetric(
                    horizontal: WpSpacing.xxs,
                  ),
                  decoration: BoxDecoration(
                    color: WpColors.accentBadgeFill,
                    borderRadius: WpRadius.borderFull,
                    border: Border.all(color: WpColors.accentBorder30),
                  ),
                  child: Text(
                    '$count',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: WpTypography.caption,
                      fontWeight: FontWeight.w600,
                      color: WpColors.accent,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.screenId, required this.section});

  final String screenId;
  final WpFilterSection section;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: '$screenId-filter-section-${section.id}',
      container: true,
      explicitChildNodes: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            section.label,
            style: TextStyle(
              fontSize: WpTypography.small,
              fontWeight: FontWeight.w600,
              color: WpColors.textMuted,
            ),
          ),
          const SizedBox(height: WpSpacing.xxs),
          Wrap(
            spacing: WpSpacing.xs,
            runSpacing: WpSpacing.xxs,
            children: section.children,
          ),
        ],
      ),
    );
  }
}

/// A compact, removable mark for one active filter.
class WpFilterMark extends StatelessWidget {
  const WpFilterMark({super.key, required this.screenId, required this.filter});

  final String screenId;
  final WpActiveFilter filter;

  @override
  Widget build(BuildContext context) {
    final accent = WpColors.accent;
    final id = '$screenId-filter-mark-${filter.id}';
    return Semantics(
      identifier: id,
      container: true,
      explicitChildNodes: true,
      child: Container(
        // Vertical 2 stays off-scale on purpose: the mark hugs its small text;
        // xxs would visibly inflate it.
        padding: const EdgeInsetsDirectional.fromSTEB(
          WpSpacing.xs + 2,
          2,
          WpSpacing.xxs,
          2,
        ),
        decoration: BoxDecoration(
          color: WpColors.accentActiveFill,
          borderRadius: WpRadius.borderFull,
          border: Border.all(color: WpColors.accentBorder30),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              filter.label,
              maxLines: 1,
              style: TextStyle(
                fontSize: WpTypography.small,
                fontWeight: FontWeight.w600,
                color: accent,
              ),
            ),
            const SizedBox(width: WpSpacing.xxxs),
            _RemoveIcon(
              testId: '$id-remove',
              color: accent,
              semanticLabel: L10n.of(
                context,
              ).collectionFilterRemove(filter.label),
              onTap: filter.onRemove,
            ),
          ],
        ),
      ),
    );
  }
}

class _RemoveIcon extends StatefulWidget {
  const _RemoveIcon({
    required this.testId,
    required this.color,
    required this.semanticLabel,
    required this.onTap,
  });

  final String testId;
  final Color color;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  State<_RemoveIcon> createState() => _RemoveIconState();
}

class _RemoveIconState extends State<_RemoveIcon> {
  final _focusNode = FocusNode(debugLabel: 'WpFilterMark.remove');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: widget.testId,
      label: widget.semanticLabel,
      button: true,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: WpFocusRing(
          focusNode: _focusNode,
          radius: WpRadius.sm,
          child: InkWell(
            key: ValueKey(widget.testId),
            onTap: widget.onTap,
            focusNode: _focusNode,
            borderRadius: WpRadius.borderSm,
            // WpFocusRing owns all focus visuals — suppress InkWell's own.
            focusColor: Colors.transparent,
            hoverColor: Colors.transparent,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.all(WpSpacing.xxxs),
              child: Icon(
                LucideIcons.x,
                size: WpIconSize.xxs,
                color: widget.color,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
