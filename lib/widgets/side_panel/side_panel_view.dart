import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/l10n/generated/app_localizations.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../services/clipboard_history/clipboard_platform_capability.dart';
import '../../services/side_panel/side_panel_row_filter.dart';
import '../../services/side_panel/side_panel_row_groups.dart';
import '../../services/side_panel/side_panel_snapshot.dart';
import '../wp_focus_ring.dart';
import '../wp_search_field.dart';
import '../wp_segmented_selector.dart';
import 'side_panel_row_tile.dart';
import '../empty_state.dart';

/// The side panel's content: one section at a time (Recordings, Snippets,
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

  /// The no-matches state's way back: empties this section's field and query.
  void _clearSearch() {
    _searchControllers[_selected]!.clear();
    _onQueryChanged('');
  }

  /// The glyph each section wears -- on its tab, on its rows' discs and on
  /// its empty state. Mirrors the main window's vocabulary: `mic` is the
  /// history type glyph, `notebookText` the snippets page's icon.
  static IconData iconOf(SidePanelSection section) => switch (section) {
    SidePanelSection.transcriptions => LucideIcons.mic,
    SidePanelSection.snippets => LucideIcons.notebookText,
    SidePanelSection.clipboardHistory => LucideIcons.clipboardList,
  };

  String _titleOf(SidePanelSection section, L10n l10n) => switch (section) {
    SidePanelSection.transcriptions => l10n.navHistory,
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
          // Linux has no background monitor: the clipboard is read once per
          // panel open, so "anything you copy" would be wrong there (PAR-005).
          clipboardHistoryCapabilityFor(defaultTargetPlatform) ==
                  ClipboardHistoryCapability.snapshotOnly
              ? l10n.sidePanelClipboardHistoryEmptyHintLinux
              : l10n.sidePanelClipboardHistoryEmptyHint,
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
                    ? WpEmptyState.panel(
                        icon: LucideIcons.triangleAlert,
                        title: l10n.errorGeneric,
                        hint: l10n.sidePanelLoadFailedHint,
                      )
                    : rows.isEmpty
                    ? WpEmptyState.panel(
                        icon: locked ? LucideIcons.lock : iconOf(_selected),
                        title: emptyTitle,
                        hint: emptyHint,
                      )
                    : filteredRows.isEmpty
                    ? WpEmptyState.panel(
                        icon: LucideIcons.searchX,
                        title: l10n.searchNoMatches,
                        hint: l10n.searchNoMatchesHint(query.trim()),
                        actionLabel: l10n.actionClearSearch,
                        actionTestId: 'side-panel-search-clear',
                        onAction: _clearSearch,
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

/// Segmented control switching the three sections, the app's shared
/// [WpSegmentedSelector] with one icon per segment: the panel is too narrow
/// for three labels. The active section's title stands in the header, and
/// every segment carries its title as tooltip and accessible name.
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
    return WpSegmentedSelector(
      borderColor: WpColors.borderDefault,
      surfaceColor: WpColors.surfaceVariant,
      textSecondary: WpColors.textSecondary,
      items: [
        for (final section in SidePanelSection.values)
          WpSegmentItem(
            label: labelOf(section),
            icon: Icon(iconOf(section)),
            iconOnly: true,
            testId: sidePanelTabTestId(section),
            isActive: section == selected,
            onTap: () => onSelect(section),
          ),
      ],
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
