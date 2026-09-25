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
///
/// [activeSectionKey] is a scroll-spy highlight (Discussion #147): it names
/// whichever section is currently at the top of the scroll view, computed by
/// [SettingsPage] from its own scroll position. Tapping a chip needs no
/// separate "just tapped" state of its own — [Scrollable.ensureVisible]'s
/// animation fires scroll notifications as it runs, so the chip bar
/// naturally lights up the target chip once the scroll settles there.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/page_state.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/wp_filter_chip.dart';
import '../search/settings_search_provider.dart';

class SettingsAnchorChipBar extends ConsumerWidget {
  const SettingsAnchorChipBar({
    super.key,
    required this.sectionKeys,
    required this.locale,
    this.activeSectionKey,
  });

  /// Section keys currently visible on the page, in display order —
  /// [SettingsPage]'s already-filtered `visibleSections` list, mapped to
  /// keys. Matches [kSettingsSearchTable]'s `sectionKey`s one-to-one.
  final List<String> sectionKeys;

  /// BCP-47 language tag used to pick each chip's localized label from
  /// [kSettingsSearchTable] — the same table backing the search dropdown.
  final String locale;

  /// The section currently at the top of the scroll view, or `null` before
  /// [SettingsPage] has measured it. Drives which chip is lit.
  final String? activeSectionKey;

  void _jumpTo(WidgetRef ref, String sectionKey) {
    // Same two-provider handshake as SettingsSearchField._selectEntry.
    ref.read(settingsScrollTargetProvider.notifier).set(sectionKey);
    ref.read(settingsHighlightTargetProvider.notifier).set(sectionKey);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = sectionKeys.toSet();
    // Iterate the search table's own order (matches SettingsPage's section
    // order) rather than sectionKeys' order, so chip order stays stable
    // even if a caller ever passes it unsorted.
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
            label: entry.title(locale),
            isActive: activeSectionKey == entry.sectionKey,
            onTap: () => _jumpTo(ref, entry.sectionKey),
          ),
      ],
    );
  }
}
