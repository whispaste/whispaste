/// Loading skeleton — list-shaped placeholder rows.
///
/// Shared by every list surface that streams its rows in (history, notes) so
/// the placeholder rhythm is defined once instead of drifting per feature.
library;

import 'package:flutter/material.dart';

import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';

/// Grey placeholder bars standing in for list rows while they load.
///
/// [rowHeight] is deliberately *not* defaulted: a skeleton only does its job
/// when its bars reserve the space the real rows will take, so each caller
/// passes the measured height of its own row. Getting it wrong is worse than
/// showing nothing — the list visibly re-flows the moment the data arrives.
class WpListSkeleton extends StatelessWidget {
  const WpListSkeleton({
    super.key,
    required this.rowHeight,
    this.count = 6,
    this.padding = const EdgeInsets.symmetric(
      horizontal: WpSpacing.md,
      vertical: WpSpacing.sm,
    ),
  });

  /// Inset of the placeholder column. Defaults to the history/notes gutter;
  /// callers whose real rows sit on a different edge pass their own so the
  /// bars land where the rows will (`WpSearchableListPage` uses `xl`).
  final EdgeInsets padding;

  /// Height of a single placeholder bar, in logical pixels — the measured
  /// height of the real row this skeleton stands in for.
  final double rowHeight;

  /// Number of placeholder bars. Six fills a typical panel without the
  /// skeleton reading as a scrollable list in its own right.
  final int count;

  @override
  Widget build(BuildContext context) {
    const boxColor = WpColors.borderSubtle;

    return ListView.separated(
      padding: padding,
      itemCount: count,
      separatorBuilder: (_, _) => const SizedBox(height: WpSpacing.xs),
      itemBuilder: (_, _) => Container(
        height: rowHeight,
        decoration: BoxDecoration(
          color: boxColor,
          borderRadius: WpRadius.borderMd,
        ),
      ),
    );
  }
}
