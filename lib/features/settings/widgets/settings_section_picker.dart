/// Section picker for the settings page, laid out on one row with the search
/// field (replaces the anchor-chip wall, concept proposal 5).
///
/// The picker is a [WpDropdown] over the same filtered section list the chip
/// bar used, and selecting an entry runs the same two-provider handshake as
/// [SettingsSearchField]: [settingsScrollTargetProvider] plus
/// [settingsHighlightTargetProvider]. [SettingsPage] owns the single
/// [ref.listen] that turns either into a [Scrollable.ensureVisible] call, so
/// the picker adds no second scroll mechanism of its own.
///
/// [activeSectionKey] is the scroll-spy highlight computed by [SettingsPage]
/// from its own scroll position. The trigger shows that section, so it stays
/// truthful while the user scrolls by hand.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/page_state.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/wp_dropdown.dart';
import '../search/settings_search_provider.dart';
import 'settings_search_field.dart';

/// Trigger width when the content area is wide (1440: search + gap + 288).
const double _kPickerWideWidth = 288;

/// Trigger width in narrower windows (800: search + gap + 232).
const double _kPickerNarrowWidth = 232;

/// Content width from which the wide trigger is used.
const double _kPickerWideBreakpoint = 960;

/// Menu width floor: the trigger width plus the check column [WpDropdown]
/// reserves in each row, so the longest section title still fits on one line
/// even when the trigger is the narrow one.
const double _kPickerMenuMinWidth = 312;

/// Narrowest search field worth keeping beside the picker before stacking.
const double _kMinSearchWidth = 200;

/// Gap between the search field and the picker when they share a row.
const double _kRowGap = WpSpacing.md;

/// Body-text scale above which the search field and picker stack instead of
/// sharing a row.
const double _kStackTextScale = 1.3;

/// Search field and section picker, sharing one row.
///
/// The search field takes the remaining width; the picker sits at the trailing
/// edge at a fixed width. Below [_kMinSearchWidth] beside the picker, or at a
/// large text scale, both controls stack, each keeping its 48 px height. With
/// no visible sections the picker is omitted and only the search field shows.
class SettingsSearchSectionRow extends StatelessWidget {
  const SettingsSearchSectionRow({
    super.key,
    required this.searchFocusNode,
    required this.sectionKeys,
    required this.locale,
    this.activeSectionKey,
  });

  final FocusNode searchFocusNode;

  /// Section keys currently visible on the page, in display order. Empty when
  /// a search leaves no section, which hides the picker.
  final List<String> sectionKeys;

  /// BCP-47 language tag used to pick each entry's localized label.
  final String locale;

  /// The section currently at the top of the scroll view, or `null` before
  /// [SettingsPage] has measured it.
  final String? activeSectionKey;

  @override
  Widget build(BuildContext context) {
    final search = SettingsSearchField(focusNode: searchFocusNode);
    if (sectionKeys.isEmpty) return search;

    final largeText =
        MediaQuery.textScalerOf(context).scale(WpTypography.body) >
        WpTypography.body * _kStackTextScale;

    Widget picker() => SettingsSectionPicker(
      sectionKeys: sectionKeys,
      locale: locale,
      activeSectionKey: activeSectionKey,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final pickerWidth = constraints.maxWidth >= _kPickerWideBreakpoint
            ? _kPickerWideWidth
            : _kPickerNarrowWidth;
        final sideBySide =
            !largeText &&
            constraints.maxWidth >= pickerWidth + _kRowGap + _kMinSearchWidth;

        if (!sideBySide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              search,
              const SizedBox(height: WpSpacing.sm),
              SizedBox(width: double.infinity, child: picker()),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: search),
            const SizedBox(width: _kRowGap),
            SizedBox(width: pickerWidth, child: picker()),
          ],
        );
      },
    );
  }
}

/// The section jump control: a [WpDropdown] whose entries are the visible
/// settings sections and whose selection scrolls to that section.
class SettingsSectionPicker extends ConsumerWidget {
  const SettingsSectionPicker({
    super.key,
    required this.sectionKeys,
    required this.locale,
    this.activeSectionKey,
  });

  /// Section keys currently visible on the page, in display order — the same
  /// filtered list [SettingsPage] builds for its sections.
  final List<String> sectionKeys;

  /// BCP-47 language tag used to pick each entry's localized label from
  /// [kSettingsSearchTable], the table backing the search dropdown.
  final String locale;

  /// Section shown on the trigger. Falls back to the first entry when it is
  /// `null` or no longer visible, so the trigger never shows a stale section.
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
    // order) rather than sectionKeys' order, so entry order stays stable.
    final entries = kSettingsSearchTable
        .where((e) => visible.contains(e.sectionKey))
        .toList(growable: false);
    if (entries.isEmpty) return const SizedBox.shrink();

    final active = activeSectionKey;
    final shownKey = entries.any((e) => e.sectionKey == active)
        ? active!
        : entries.first.sectionKey;

    return WpDropdown<String>(
      key: const Key('settings-section-picker'),
      value: shownKey,
      items: [
        for (final entry in entries)
          WpDropdownItem<String>(
            value: entry.sectionKey,
            label: entry.title(locale),
            itemKey: Key('settings-section-picker-${entry.sectionKey}'),
          ),
      ],
      onChanged: (sectionKey) {
        if (sectionKey != null) _jumpTo(ref, sectionKey);
      },
      expanded: true,
      menuMinWidth: _kPickerMenuMinWidth,
    );
  }
}
