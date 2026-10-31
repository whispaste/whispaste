import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/l10n/generated/app_localizations.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../services/side_panel/side_panel_row_filter.dart';
import '../../services/side_panel/side_panel_row_groups.dart';
import '../../services/side_panel/side_panel_snapshot.dart';
import '../wp_focus_ring.dart';
import '../wp_search_field.dart';
import 'side_panel_focus_tooltip.dart';
import 'side_panel_row_tile.dart';

/// The side panel's content: one section at a time (Transcriptions, Snippets,
/// Clipboard History), switched by an icon tab bar, each with its own empty
/// state.
///
/// Pure widget -- takes a [SidePanelSnapshot] and two callbacks, nothing
/// else. No channels, no natives, no Riverpod: [SidePanelService] assembles
/// the snapshot from the real providers and owns the click→insert action;
/// this widget only renders and reports which row was tapped (or that the
/// close button asked the panel to close). The selected tab is pure render
/// state: the full snapshot for all three sections arrives on every update
/// regardless of which tab is showing.
///
/// The panel window is a transparent canvas anchored flush against the
/// screen edge named by [SidePanelSnapshot.edge], so the surface painted here
/// *is* the panel's silhouette: only the screen-facing corners are rounded,
/// the docked edge stays hard, and the close button sits on the
/// screen-facing side.
class WpSidePanelView extends StatefulWidget {
  const WpSidePanelView({
    super.key,
    required this.snapshot,
    required this.onRowTap,
    required this.onClose,
    this.onRowDragStart,
  });

  final SidePanelSnapshot snapshot;
  final void Function(SidePanelSection section, String id) onRowTap;

  /// Asks the owner to close the panel -- wired to the same
  /// `hoverLeft` path the hover-exit close already uses.
  final VoidCallback onClose;

  /// Fires once a row's drag gesture has been recognized (issue 11) -- null
  /// in tests/contexts that don't care about drag-out, in which case rows
  /// stay click-only.
  final void Function(SidePanelSection section, SidePanelRow row)?
  onRowDragStart;

  @override
  State<WpSidePanelView> createState() => _WpSidePanelViewState();
}

class _WpSidePanelViewState extends State<WpSidePanelView> {
  SidePanelSection _selected = SidePanelSection.transcriptions;

  /// One query string per section (issue 09) -- a filter typed while
  /// viewing Snippets must not touch what Transcriptions or Clipboard
  /// History show, so each section keeps its own, independent of which tab
  /// is currently active.
  final Map<SidePanelSection, String> _queries = {
    for (final section in SidePanelSection.values) section: '',
  };

  /// One controller per section so the single, persistent search field
  /// below the tab bar can be rebound to whichever section is active
  /// (`WpSearchField.didUpdateWidget` handles the listener rewiring) while
  /// still showing that section's own saved query text after a tab switch.
  final Map<SidePanelSection, TextEditingController> _searchControllers = {
    for (final section in SidePanelSection.values)
      section: TextEditingController(),
  };

  @override
  void dispose() {
    for (final controller in _searchControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _onQueryChanged(String query) {
    setState(() => _queries[_selected] = query);
  }

  /// The glyph each section wears -- on its tab, on its rows' discs and on
  /// its empty state. Mirrors the main window's vocabulary: `mic` is the
  /// history avatar glyph, `notebookText` the snippets page's icon.
  static IconData iconOf(SidePanelSection section) => switch (section) {
    SidePanelSection.transcriptions => LucideIcons.mic,
    SidePanelSection.snippets => LucideIcons.notebookText,
    SidePanelSection.clipboardHistory => LucideIcons.clipboardList,
  };

  String _titleOf(SidePanelSection section, L10n l10n) => switch (section) {
    SidePanelSection.transcriptions => l10n.sidePanelTranscriptionsTitle,
    SidePanelSection.snippets => l10n.sidePanelSnippetsTitle,
    SidePanelSection.clipboardHistory => l10n.sidePanelClipboardHistoryTitle,
  };

  List<SidePanelRow> _rowsOf(SidePanelSection section) => switch (section) {
    SidePanelSection.transcriptions => widget.snapshot.transcriptions,
    SidePanelSection.snippets => widget.snapshot.snippets,
    SidePanelSection.clipboardHistory => widget.snapshot.clipboardHistory,
  };

  (String, String) _emptyOf(SidePanelSection section, L10n l10n) =>
      switch (section) {
        SidePanelSection.transcriptions => (
          l10n.historyEmpty,
          l10n.historyEmptyHint,
        ),
        SidePanelSection.snippets => (
          l10n.snippetsEmpty,
          l10n.snippetsEmptyHint,
        ),
        SidePanelSection.clipboardHistory => (
          l10n.sidePanelClipboardHistoryEmpty,
          l10n.sidePanelClipboardHistoryEmptyHint,
        ),
      };

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    // A PIN-locked clipboard tab renders no rows at all (GS-125), even if the
    // snapshot carried some.
    final locked =
        _selected == SidePanelSection.clipboardHistory &&
        widget.snapshot.clipboardLocked;
    final rows = locked ? const <SidePanelRow>[] : _rowsOf(_selected);
    final loadFailed =
        !locked && widget.snapshot.failedSections.contains(_selected);
    final query = _queries[_selected]!;
    final filteredRows = filterSidePanelRows(rows, query);
    final (emptyTitle, emptyHint) = locked
        ? (
            l10n.sidePanelClipboardLockedTitle,
            l10n.sidePanelClipboardLockedHint,
          )
        : _emptyOf(_selected, l10n);
    final switchDuration = WpMotion.durationFor(context, WpMotion.normal);

    final dockedRight = widget.snapshot.edge == 'right';
    const round = Radius.circular(WpRadius.xl);
    final closeButton = _CloseButton(
      testId: 'side-panel-close',
      label: l10n.sidePanelClose,
      onTap: widget.onClose,
    );

    final panel = Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: WpColors.surfaceGradient,
        // Flush against the docked screen edge: only the screen-facing side
        // reads as a floating rounded slide-out, the docked edge stays hard.
        borderRadius: dockedRight
            ? const BorderRadius.only(topLeft: round, bottomLeft: round)
            : const BorderRadius.only(topRight: round, bottomRight: round),
        // The rim every floating surface wears (see `floatingSurface` in
        // colors.dart). Uniform because Flutter cannot pair a non-uniform
        // Border with a borderRadius; the docked run vanishes off-screen.
        border: Border.all(color: WpColors.cardEdgeHighlight, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              WpSpacing.md,
              WpSpacing.md,
              WpSpacing.md,
              WpSpacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  // Physical order: the close button follows the docked
                  // screen edge, not the reading direction.
                  textDirection: TextDirection.ltr,
                  children: [
                    if (dockedRight) ...[
                      closeButton,
                      const SizedBox(width: WpSpacing.xs),
                    ],
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: switchDuration,
                        layoutBuilder: _startAlignedSwitcherLayout,
                        child: Text(
                          _titleOf(_selected, l10n),
                          key: ValueKey(_selected),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: WpColors.textPrimary,
                            fontSize: WpTypography.heading,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    if (!dockedRight) ...[
                      const SizedBox(width: WpSpacing.xs),
                      closeButton,
                    ],
                  ],
                ),
                const SizedBox(height: WpSpacing.sm),
                _SidePanelTabBar(
                  selected: _selected,
                  labelOf: (section) => _titleOf(section, l10n),
                  iconOf: iconOf,
                  onSelect: (section) => setState(() => _selected = section),
                ),
                const SizedBox(height: WpSpacing.sm),
                WpSearchField(
                  key: ValueKey(_selected),
                  testId: 'side-panel-search',
                  controller: _searchControllers[_selected]!,
                  hintText: l10n.sidePanelSearchHint,
                  variant: WpSearchFieldVariant.capsule,
                  onChanged: _onQueryChanged,
                  semanticsLabel: l10n.sidePanelSearchFieldLabel,
                ),
              ],
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: switchDuration,
              switchInCurve: WpMotion.defaultCurve,
              switchOutCurve: WpMotion.defaultCurve,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.015),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: KeyedSubtree(
                key: ValueKey(_selected),
                child: loadFailed
                    ? _EmptySectionState(
                        icon: LucideIcons.triangleAlert,
                        title: l10n.errorGeneric,
                        hint: l10n.sidePanelLoadFailedHint,
                      )
                    : rows.isEmpty
                    ? _EmptySectionState(
                        icon: locked ? LucideIcons.lock : iconOf(_selected),
                        title: emptyTitle,
                        hint: emptyHint,
                      )
                    : filteredRows.isEmpty
                    ? _EmptySectionState(
                        icon: LucideIcons.searchX,
                        title: l10n.sidePanelNoMatches,
                        hint: l10n.sidePanelNoMatchesHint,
                      )
                    : _SidePanelList(
                        items: groupSidePanelRows(
                          filteredRows,
                          now: DateTime.now(),
                          todayLabel: l10n.historyToday,
                          yesterdayLabel: l10n.historyYesterday,
                          locale: Localizations.localeOf(context).toString(),
                        ),
                        leadingIcon: iconOf(_selected),
                        kindLabel: _titleOf(_selected, l10n),
                        onRowTap: (row) => widget.onRowTap(_selected, row.id),
                        onRowDragStart: widget.onRowDragStart == null
                            ? null
                            : (row) => widget.onRowDragStart!(_selected, row),
                      ),
              ),
            ),
          ),
        ],
      ),
    );

    // Escape closes the panel from anywhere inside it, the same way the
    // close button does. Arrow keys, Tab and Enter already traverse and
    // activate rows through the standard focus actions.
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
      },
      child: panel,
    );
  }

  /// [AnimatedSwitcher]'s default layout centers its children, which makes a
  /// start-aligned title hop horizontally while two widths cross-fade.
  static Widget _startAlignedSwitcherLayout(
    Widget? currentChild,
    List<Widget> previousChildren,
  ) {
    return Stack(
      alignment: AlignmentDirectional.centerStart,
      children: [...previousChildren, ?currentChild],
    );
  }
}

/// Lazily built list of day headers and rows. Only visible items are built,
/// so a long history stays cheap to scroll.
class _SidePanelList extends StatelessWidget {
  const _SidePanelList({
    required this.items,
    required this.leadingIcon,
    required this.kindLabel,
    required this.onRowTap,
    this.onRowDragStart,
  });

  final List<SidePanelListItem> items;
  final IconData leadingIcon;

  /// Localized name of the active section, spoken before each row's title.
  final String kindLabel;
  final void Function(SidePanelRow row) onRowTap;
  final void Function(SidePanelRow row)? onRowDragStart;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: 'side-panel-list',
      explicitChildNodes: true,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(
          WpSpacing.md,
          WpSpacing.xxs,
          WpSpacing.md,
          // Bottom room so the last row scrolls clear of the panel edge.
          WpSpacing.xl,
        ),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return switch (item) {
            SidePanelDateHeader(:final label, :final day) =>
              _SidePanelDateHeader(label: label, day: day),
            SidePanelRowItem(:final row) =>
              // loam-ignore: a11y-interactive-semantics – Semantics lives inside WpSidePanelRowTile
              WpSidePanelRowTile(
                row: row,
                leadingIcon: leadingIcon,
                kindLabel: kindLabel,
                onTap: () => onRowTap(row),
                onDragStart: onRowDragStart == null
                    ? null
                    : () => onRowDragStart!(row),
              ),
          };
        },
      ),
    );
  }
}

/// Muted day label between row groups.
class _SidePanelDateHeader extends StatelessWidget {
  const _SidePanelDateHeader({required this.label, required this.day});

  final String label;
  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final dayKey =
        '${day.year.toString().padLeft(4, '0')}-'
        '${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}';
    return Semantics(
      header: true,
      identifier: 'side-panel-day-$dayKey',
      child: Padding(
        // Directional, so the indent sits on the reading-start side in RTL.
        padding: const EdgeInsetsDirectional.only(
          top: WpSpacing.sm,
          bottom: WpSpacing.xxs,
          start: WpSpacing.xxs,
        ),
        child: Text(
          label,
          textScaler: sidePanelTextScaler(context),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: WpColors.textMuted,
            fontSize: WpTypography.caption,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// Segmented control switching the three sections: icon plus label per
/// segment. The label is ellipsized when the panel is at its minimum width,
/// so each segment always carries its full title as a tooltip and as its
/// semantics label.
class _SidePanelTabBar extends StatelessWidget {
  const _SidePanelTabBar({
    required this.selected,
    required this.labelOf,
    required this.iconOf,
    required this.onSelect,
  });

  final SidePanelSection selected;
  final String Function(SidePanelSection section) labelOf;
  final IconData Function(SidePanelSection section) iconOf;
  final void Function(SidePanelSection section) onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      // Off-scale on purpose: a 3px gutter hugs the segments the way the
      // avatar's rim hugs its disc; xxs would double the track's height.
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: WpColors.cardFill,
        borderRadius: WpRadius.borderMd,
        border: Border.all(color: WpColors.borderSubtle, width: 1),
      ),
      child: Row(
        children: [
          for (final section in SidePanelSection.values)
            Expanded(
              child: _SidePanelTab(
                testId: sidePanelTabTestId(section),
                icon: iconOf(section),
                label: labelOf(section),
                isSelected: section == selected,
                onTap: () => onSelect(section),
              ),
            ),
        ],
      ),
    );
  }
}

/// Stable, language-independent id of a section's tab.
String sidePanelTabTestId(SidePanelSection section) => switch (section) {
  SidePanelSection.transcriptions => 'side-panel-tab-transcriptions',
  SidePanelSection.snippets => 'side-panel-tab-snippets',
  SidePanelSection.clipboardHistory => 'side-panel-tab-clipboard-history',
};

/// Largest text scale the side panel renders at. The panel is 290 px wide,
/// so beyond 2x its tabs and headers cannot fit anyway.
const double kSidePanelMaxTextScale = 2.0;

TextScaler sidePanelTextScaler(BuildContext context) => MediaQuery.textScalerOf(
  context,
).clamp(maxScaleFactor: kSidePanelMaxTextScale);

class _SidePanelTab extends StatefulWidget {
  const _SidePanelTab({
    required this.testId,
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String testId;
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  State<_SidePanelTab> createState() => _SidePanelTabState();
}

class _SidePanelTabState extends State<_SidePanelTab> {
  bool _isHovered = false;
  final FocusNode _focusNode = FocusNode(debugLabel: 'SidePanelTab');

  /// Set during layout: whether the label is cut off at the current text
  /// scale. Read by [WpSidePanelFocusTooltip] on focus changes.
  bool _labelTruncated = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isActive = widget.isSelected || _isHovered;
    final tone = widget.isSelected
        ? WpColors.accent
        : _isHovered
        ? WpColors.textSecondary
        : WpColors.textMuted;
    // One semantics node per tab: the Semantics label names it, so the icon
    // and text inside are excluded. The tooltip shows on pointer hover; the
    // label is what keyboard focus announces.
    return Semantics(
      identifier: widget.testId,
      button: true,
      selected: widget.isSelected,
      label: widget.label,
      onTap: widget.onTap,
      child: ExcludeSemantics(
        child: WpSidePanelFocusTooltip(
          message: widget.label,
          focusNode: _focusNode,
          isTruncated: () => _labelTruncated,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _isHovered = true),
            onExit: (_) => setState(() => _isHovered = false),
            child: WpFocusRing(
              focusNode: _focusNode,
              radius: WpRadius.sm,
              child: InkWell(
                onTap: widget.onTap,
                focusNode: _focusNode,
                borderRadius: WpRadius.borderSm,
                focusColor: Colors.transparent,
                hoverColor: Colors.transparent,
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
                child: AnimatedContainer(
                  duration: WpMotion.durationFor(
                    context,
                    isActive ? WpMotion.hoverIn : WpMotion.hoverOut,
                  ),
                  curve: WpMotion.defaultCurve,
                  // 48 px minimum target; grows with the text scale.
                  constraints: const BoxConstraints(minHeight: 48),
                  decoration: BoxDecoration(
                    color: widget.isSelected
                        ? WpColors.accentActiveFill
                        : _isHovered
                        ? WpColors.hover
                        : WpColors.hoverTransparent,
                    borderRadius: WpRadius.borderSm,
                    // Never null -- animates its alpha, so the selection edge
                    // fades instead of flashing (see wp_list_tile_surface.dart).
                    border: Border.all(
                      color: widget.isSelected
                          ? WpColors.accentBorder20
                          : WpColors.accent.withValues(alpha: 0),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(widget.icon, size: WpIconSize.sm, color: tone),
                      const SizedBox(width: WpSpacing.xxs),
                      Flexible(
                        // Measures the slot the label gets, to know whether
                        // the focus tooltip is needed (see _labelTruncated).
                        child: LayoutBuilder(
                          builder: (context, box) {
                            final scaler = sidePanelTextScaler(context);
                            final style = TextStyle(
                              color: tone,
                              fontSize: WpTypography.caption,
                              fontWeight: widget.isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            );
                            _labelTruncated = isOneLineTruncated(
                              context,
                              text: widget.label,
                              style: style,
                              textScaler: scaler,
                              maxWidth: box.maxWidth,
                            );
                            return Text(
                              widget.label,
                              textScaler: scaler,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: style,
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
    );
  }
}

class _CloseButton extends StatefulWidget {
  const _CloseButton({
    required this.testId,
    required this.label,
    required this.onTap,
  });

  final String testId;
  final String label;
  final VoidCallback onTap;

  @override
  State<_CloseButton> createState() => _CloseButtonState();
}

class _CloseButtonState extends State<_CloseButton> {
  bool _isHovered = false;
  final FocusNode _focusNode = FocusNode(debugLabel: 'CloseButton');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: widget.testId,
      button: true,
      label: widget.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: WpFocusRing(
          focusNode: _focusNode,
          radius: WpRadius.sm,
          child: InkWell(
            onTap: widget.onTap,
            focusNode: _focusNode,
            borderRadius: WpRadius.borderSm,
            focusColor: Colors.transparent,
            hoverColor: Colors.transparent,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            child: AnimatedContainer(
              duration: WpMotion.durationFor(
                context,
                _isHovered ? WpMotion.hoverIn : WpMotion.hoverOut,
              ),
              curve: WpMotion.defaultCurve,
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: _isHovered ? WpColors.hover : WpColors.hoverTransparent,
                borderRadius: WpRadius.borderSm,
              ),
              child: Icon(
                LucideIcons.x,
                size: WpIconSize.md,
                color: _isHovered ? WpColors.textPrimary : WpColors.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptySectionState extends StatelessWidget {
  const _EmptySectionState({
    required this.icon,
    required this.title,
    required this.hint,
  });

  final IconData icon;
  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: WpSpacing.xl,
          vertical: WpSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: WpIconSize.xl, color: WpColors.textMuted),
            const SizedBox(height: WpSpacing.sm),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: WpColors.textSecondary,
                fontSize: WpTypography.body,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: WpSpacing.xxs),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: WpColors.textMuted,
                fontSize: WpTypography.caption,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
