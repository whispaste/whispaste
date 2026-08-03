import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/wp_focus_ring.dart';
import '../data/providers.dart';

// ---------------------------------------------------------------------------
// Notes filter bar — Ticket-04 scope: just the active/trash toggle. The
// search field docks in here with Ticket 06 (hence the file name).
// ---------------------------------------------------------------------------

class NotesSearchBar extends StatelessWidget {
  const NotesSearchBar({
    super.key,
    required this.currentFilter,
    required this.onFilterChanged,
    required this.isDark,
  });

  final NotesFilter currentFilter;
  final ValueChanged<NotesFilter> onFilterChanged;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: WpSpacing.md),
      child: Row(
        children: [
          // loam-ignore: a11y-interactive-semantics – semantics provided in
          // _NotesFilterChipState.build
          _NotesFilterChip(
            label: l10n.navNotes,
            icon: LucideIcons.stickyNote,
            isActive: currentFilter == NotesFilter.active,
            isDark: isDark,
            onTap: () => onFilterChanged(NotesFilter.active),
          ),
          const SizedBox(width: WpSpacing.xs),
          // loam-ignore: a11y-interactive-semantics – semantics provided in
          // _NotesFilterChipState.build
          _NotesFilterChip(
            label: l10n.notesTrash,
            icon: LucideIcons.trash2,
            isActive: currentFilter == NotesFilter.trash,
            isDark: isDark,
            onTap: () => onFilterChanged(NotesFilter.trash),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Filter chip — visual sibling of HistoryFilterChip (same pill proportions
// and state colors), deliberately re-implemented here: Notizen must not take
// a feature-to-feature dependency on History (Ticket-02 architecture rule),
// and this variant needs no count badge.
// ---------------------------------------------------------------------------

class _NotesFilterChip extends StatefulWidget {
  const _NotesFilterChip({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.isDark,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isActive;
  final bool isDark;
  final VoidCallback onTap;

  @override
  State<_NotesFilterChip> createState() => _NotesFilterChipState();
}

class _NotesFilterChipState extends State<_NotesFilterChip> {
  bool _isHovered = false;
  final FocusNode _focusNode = FocusNode(debugLabel: 'NotesFilterChip');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final Color bg;
    final Color fg;
    if (widget.isActive) {
      bg = isDark ? WpColorsDark.accentSubtle : WpColorsLight.accentSubtle;
      fg = isDark ? WpColorsDark.accent : WpColorsLight.accent;
    } else if (_isHovered) {
      bg = isDark ? WpColorsDark.hover : WpColorsLight.hover;
      fg = isDark ? WpColorsDark.textPrimary : WpColorsLight.textPrimary;
    } else {
      bg = isDark ? WpColorsDark.surfaceVariant : WpColorsLight.surfaceVariant;
      fg = isDark ? WpColorsDark.textSecondary : WpColorsLight.textSecondary;
    }

    // Compact visual pill — the tap/focus surface around it stretches to
    // WpLayout.minTouchTarget height via the InkWell below.
    final pill = AnimatedContainer(
      duration: WpMotion.durationFor(
        context,
        _isHovered ? WpMotion.hoverIn : WpMotion.hoverOut,
      ),
      curve: WpMotion.defaultCurve,
      // Off-scale on purpose: 12x6 pill proportion shared with the history
      // filter chips so both areas' filter rows read identically.
      padding: const EdgeInsets.symmetric(
        horizontal: WpSpacing.sm,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: WpRadius.borderFull,
        border: widget.isActive
            ? Border.all(
                color: isDark
                    ? WpColorsDark.accentBorder30
                    : WpColorsLight.accentBorder30,
              )
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(widget.icon, size: WpIconSize.sm, color: fg),
          const SizedBox(width: WpSpacing.xxs),
          Text(
            widget.label,
            style: TextStyle(
              color: fg,
              fontSize: WpTypography.body,
              height: 1.15,
              fontWeight: widget.isActive ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );

    return Semantics(
      label: widget.label,
      button: true,
      selected: widget.isActive,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: InkWell(
          onTap: widget.onTap,
          focusNode: _focusNode,
          // WpFocusRing owns all focus visuals — suppress InkWell's own.
          focusColor: Colors.transparent,
          hoverColor: Colors.transparent,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: WpLayout.minTouchTarget,
            ),
            child: Center(
              child: WpFocusRing(
                focusNode: _focusNode,
                radius: WpRadius.lg,
                child: pill,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
