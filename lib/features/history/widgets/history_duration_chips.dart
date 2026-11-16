import 'package:flutter/material.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/wp_filter_chip.dart';
import '../data/providers.dart';

/// The visible name of [bucket], shared by the chip, its mark and the empty
/// state.
String historyDurationLabel(L10n l10n, HistoryDurationBucket bucket) =>
    switch (bucket) {
      HistoryDurationBucket.all => l10n.historyDurationAll,
      HistoryDurationBucket.short => l10n.historyDurationShort,
      HistoryDurationBucket.medium => l10n.historyDurationMedium,
      HistoryDurationBucket.long => l10n.historyDurationLong,
    };

/// One-click duration filter for the History list (#879): "All", under 1 min,
/// 1–5 min, over 5 min. Exactly one chip is active; it narrows whatever the
/// search, the period and the pinned/archive/trash filter already return.
/// Lives in the filter popover (#1201).
class HistoryDurationChips extends StatelessWidget {
  const HistoryDurationChips({
    super.key,
    required this.active,
    required this.onChanged,
  });

  final HistoryDurationBucket active;
  final ValueChanged<HistoryDurationBucket> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Wrap(
      spacing: WpSpacing.xs,
      runSpacing: WpSpacing.xxs,
      children: [
        for (final bucket in HistoryDurationBucket.values)
          WpFilterChip(
            testId: 'history-duration-${bucket.token}',
            label: historyDurationLabel(l10n, bucket),
            isActive: bucket == active,
            onTap: () => onChanged(bucket),
          ),
      ],
    );
  }
}
