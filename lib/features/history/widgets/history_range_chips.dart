import 'package:flutter/material.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/wp_filter_chip.dart';
import '../data/search_query_parser.dart';

/// Visible name of the period [range], shared by the chip and its mark.
String historyRangeLabel(L10n l10n, HistoryDateRange range) => switch (range) {
  HistoryDateRange.today => l10n.historyToday,
  HistoryDateRange.yesterday => l10n.historyRangeYesterday,
  HistoryDateRange.last7Days => l10n.historyRangeLast7,
  HistoryDateRange.last30Days => l10n.historyRangeLast30,
  HistoryDateRange.monthToDate => l10n.historyRangeMonth,
};

/// One-click period filter for the History list, in the filter popover.
///
/// The chips write the same operators the search field understands
/// (`date:7d`, see `search_query_parser.dart`), so a chip and a typed operator
/// are one and the same filter: typing selects the chip, clicking shows the
/// operator in the field and as a removable mark next to the search. Length
/// has one click path only, the duration chips (`HistoryDurationChips`);
/// `longer:` and `shorter:` stay operators to type (#1176).
class HistoryRangeChips extends StatelessWidget {
  const HistoryRangeChips({
    super.key,
    required this.parsed,
    required this.query,
    required this.onQueryChanged,
  });

  final ParsedSearchQuery parsed;

  /// The current text of the search field.
  final String query;

  /// Receives the whole new search text.
  final ValueChanged<String> onQueryChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Wrap(
      spacing: WpSpacing.xs,
      runSpacing: WpSpacing.xxs,
      children: [
        for (final range in HistoryDateRange.values)
          WpFilterChip(
            testId: 'history-range-${range.token}',
            label: historyRangeLabel(l10n, range),
            isActive: parsed.dateRange == range,
            onTap: () => onQueryChanged(withDateOperator(query, range)),
          ),
        WpFilterChip(
          testId: 'history-range-any',
          label: l10n.historyRangeAny,
          isActive: parsed.dateRange == null,
          onTap: () => onQueryChanged(withDateOperator(query, null)),
        ),
      ],
    );
  }
}
