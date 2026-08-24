import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/l10n/generated/app_localizations.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../services/side_panel/side_panel_row_filter.dart';
import '../../services/side_panel/side_panel_snapshot.dart';
import '../wp_search_field.dart';
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
/// The panel window is a transparent canvas anchored flush against the left
/// screen edge, so the surface painted here *is* the panel's silhouette:
/// only the right-hand corners are rounded and the left edge stays hard.
class WpSidePanelView extends StatefulWidget {
  const WpSidePanelView({
    super.key,
    required this.snapshot,
    required this.onRowTap,
    required this.onClose,
  });

  final SidePanelSnapshot snapshot;
  final void Function(SidePanelSection section, String id) onRowTap;

  /// Asks the owner to close the panel -- wired to the same
  /// `hoverLeft` path the hover-exit close already uses.
  final VoidCallback onClose;

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
    final rows = _rowsOf(_selected);
    final query = _queries[_selected]!;
    final filteredRows = filterSidePanelRows(rows, query);
    final (emptyTitle, emptyHint) = _emptyOf(_selected, l10n);
    final switchDuration = WpMotion.durationFor(context, WpMotion.normal);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: WpColors.surfaceGradient,
        // Flush against the left screen edge: only the right side reads as
        // a floating rounded slide-out, the left edge stays hard.
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(WpRadius.xl),
          bottomRight: Radius.circular(WpRadius.xl),
        ),
        // The rim every floating surface wears (see `floatingSurface` in
        // colors.dart). Uniform because Flutter cannot pair a non-uniform
        // Border with a borderRadius; the left run vanishes off-screen.
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
                  children: [
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: switchDuration,
                        layoutBuilder: _startAlignedSwitcherLayout,
                        child: Text(
                          _titleOf(_selected, l10n),
                          key: ValueKey(_selected),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: WpColors.textPrimary,
                            fontSize: WpTypography.heading,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: WpSpacing.xs),
                    _CloseButton(
                      label: l10n.sidePanelClose,
                      onTap: widget.onClose,
                    ),
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
                child: rows.isEmpty
                    ? _EmptySectionState(
                        icon: iconOf(_selected),
                        title: emptyTitle,
                        hint: emptyHint,
                      )
                    : filteredRows.isEmpty
                    ? _EmptySectionState(
                        icon: LucideIcons.searchX,
                        title: l10n.sidePanelNoMatches,
                        hint: l10n.sidePanelNoMatchesHint,
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(
                          WpSpacing.md,
                          WpSpacing.xxs,
                          WpSpacing.md,
                          WpSpacing.md,
                        ),
                        // No per-row bottom Padding wrapper (issue 08) --
                        // WpListTileSurface.panelVerticalMargin alone
                        // governs row spacing, same as HistoryListView and
                        // NotesListView, instead of stacking an extra
                        // WpSpacing.xxs gap on top of it.
                        children: [
                          for (final row in filteredRows)
                            // loam-ignore: a11y-interactive-semantics – Semantics lives inside WpSidePanelRowTile
                            WpSidePanelRowTile(
                              row: row,
                              leadingIcon: iconOf(_selected),
                              onTap: () => widget.onRowTap(_selected, row.id),
                            ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
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

/// Icon segmented control switching the three sections. Icon-only because
/// three localized titles ("Zwischenablage-Verlauf") cannot share ~290px;
/// the active section's title is spelled out in the header above, and each
/// segment carries the full title as its semantics label.
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

class _SidePanelTab extends StatefulWidget {
  const _SidePanelTab({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  State<_SidePanelTab> createState() => _SidePanelTabState();
}

class _SidePanelTabState extends State<_SidePanelTab> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isActive = widget.isSelected || _isHovered;
    return Semantics(
      button: true,
      selected: widget.isSelected,
      label: widget.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: WpMotion.durationFor(
              context,
              isActive ? WpMotion.hoverIn : WpMotion.hoverOut,
            ),
            curve: WpMotion.defaultCurve,
            height: 28,
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
                    : const Color(0x006FDDF0),
                width: 1,
              ),
            ),
            child: Icon(
              widget.icon,
              size: WpIconSize.md,
              color: widget.isSelected
                  ? WpColors.accent
                  : _isHovered
                  ? WpColors.textSecondary
                  : WpColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _CloseButton extends StatefulWidget {
  const _CloseButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  State<_CloseButton> createState() => _CloseButtonState();
}

class _CloseButtonState extends State<_CloseButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
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
              style: const TextStyle(
                color: WpColors.textSecondary,
                fontSize: WpTypography.body,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: WpSpacing.xxs),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: const TextStyle(
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
