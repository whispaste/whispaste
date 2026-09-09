/// Anchor-/jump-chip bar shown above the settings scroll view (Ticket 16,
/// implementing the variant Ticket 15 chose).
///
/// One chip per currently visible settings section. Tapping a chip scrolls
/// that section into view — the *same* deep-link plumbing
/// [SettingsSearchField] already drives when a search suggestion is
/// selected: [settingsScrollTargetProvider] plus
/// [settingsHighlightTargetProvider]. [SettingsPage] owns the single
/// [ref.listen] that turns either into a [Scrollable.ensureVisible] call, so
/// this bar adds no second scroll mechanism of its own.
///
/// Ticket 15's decision (a) — a chip bar over the existing single-page view
/// rather than categorized sub-pages — exists specifically so the page's
/// full-text search stays untouched. This bar honors that by taking the
/// exact filtered [sectionKeys] list [SettingsPage] already computes for the
/// search/platform/onboarding gating: it renders no chip of its own accord
/// and disappears along with a section the moment search hides it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/page_state.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/wp_filter_chip.dart';
import '../search/settings_search_provider.dart';

class SettingsAnchorChipBar extends ConsumerStatefulWidget {
  const SettingsAnchorChipBar({
    super.key,
    required this.sectionKeys,
    required this.locale,
  });

  /// Section keys currently visible on the page, in display order —
  /// [SettingsPage]'s already-filtered `visibleSections` list, mapped to
  /// keys. Matches [kSettingsSearchTable]'s `sectionKey`s one-to-one.
  final List<String> sectionKeys;

  /// BCP-47 language tag used to pick each chip's localized label from
  /// [kSettingsSearchTable] — the same table backing the search dropdown.
  final String locale;

  @override
  ConsumerState<SettingsAnchorChipBar> createState() =>
      _SettingsAnchorChipBarState();
}

class _SettingsAnchorChipBarState extends ConsumerState<SettingsAnchorChipBar> {
  // Purely cosmetic "last tapped" feedback, not a scroll-spy: keeping this in
  // sync with free scrolling would need a listener on the shell's own scroll
  // controller for a behaviour the ticket never asks for. A chip that lights
  // up on tap and stays lit until another chip is tapped is the smaller,
  // honest surface — it never claims to track a position it does not watch.
  String? _lastTapped;

  void _jumpTo(String sectionKey) {
    setState(() => _lastTapped = sectionKey);
    // Same two-provider handshake as SettingsSearchField._selectEntry.
    ref.read(settingsScrollTargetProvider.notifier).set(sectionKey);
    ref.read(settingsHighlightTargetProvider.notifier).set(sectionKey);
  }

  @override
  Widget build(BuildContext context) {
    final visible = widget.sectionKeys.toSet();
    // Iterate the search table's own order (matches SettingsPage's section
    // order) rather than widget.sectionKeys' order, so chip order stays
    // stable even if a caller ever passes it unsorted.
    final entries = kSettingsSearchTable.where(
      (e) => visible.contains(e.sectionKey),
    );

    // Wrap, not a horizontal scroller: every chip stays discoverable at a
    // glance even in a narrow window, matching WpFilterChip's other call
    // sites (HistorySearchFilterBar, NotesSearchBar) rather than hiding
    // chips behind an undiscoverable side-scroll gesture.
    return Wrap(
      spacing: WpSpacing.xs,
      runSpacing: WpSpacing.xxs,
      children: [
        for (final entry in entries)
          WpFilterChip(
            label: entry.title(widget.locale),
            isActive: _lastTapped == entry.sectionKey,
            onTap: () => _jumpTo(entry.sectionKey),
          ),
      ],
    );
  }
}
