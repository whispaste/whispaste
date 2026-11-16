/// Review page between a CSV file and the replacement list. Shows the package
/// header, the counts for the chosen conflict strategy, every row with its
/// status, and the lines that could not be read. The plan shown here is the
/// plan that gets written, and nothing is written until the user confirms.
library;

import 'package:flutter/material.dart';

import '../../core/l10n/generated/app_localizations.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../services/dictionary/replacement_csv.dart';
import '../../services/dictionary/replacement_import_plan.dart';
import '../../services/replacements/text_replacement_matcher.dart';
import '../../widgets/wp_banner.dart';
import '../../widgets/wp_button.dart';
import '../../widgets/wp_row_checkbox.dart';
import '../../widgets/wp_segmented_selector.dart';

class DictionaryCsvPreviewPage extends StatefulWidget {
  const DictionaryCsvPreviewPage({
    super.key,
    required this.result,
    required this.existing,
  });

  final ReplacementCsvParseResult result;

  /// The entries already in the list, as the planner needs them.
  final List<ReplacementImportExisting> existing;

  @override
  State<DictionaryCsvPreviewPage> createState() =>
      _DictionaryCsvPreviewPageState();
}

class _DictionaryCsvPreviewPageState extends State<DictionaryCsvPreviewPage> {
  ReplacementImportStrategy _strategy = ReplacementImportStrategy.skip;

  /// Rows the user took out of the import (UIA-DIC-12). Only rows that would
  /// be added can be unticked.
  final Set<int> _unticked = {};

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    // With every row ticked, the rows that would be added get a box.
    final all = planReplacementImport(
      rows: widget.result.rows,
      existing: widget.existing,
      strategy: _strategy,
    );
    // The plan that gets written only contains the ticked rows.
    final tickedIndex = [
      for (var i = 0; i < widget.result.rows.length; i++)
        if (!_unticked.contains(i)) i,
    ];
    final plan = planReplacementImport(
      rows: [for (final i in tickedIndex) widget.result.rows[i]],
      existing: widget.existing,
      strategy: _strategy,
    );
    final statusByRow = {
      for (var k = 0; k < tickedIndex.length; k++)
        tickedIndex[k]: plan.statuses[k],
    };
    // Rows with a trigger that never fires are still imported; the preview
    // only says how many of them the file holds.
    final neverFiresCount = widget.result.rows
        .where((r) => r.triggers.any(exactTriggerNeverFires))
        .length;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.dictionaryCsvPreviewTitle)),
      body: ListView(
        padding: const EdgeInsets.all(WpSpacing.lg),
        children: [
          Text(
            key: const ValueKey('dictionary-csv-preview-header'),
            _packageHeader(context, l10n),
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: WpSpacing.sm),
          Text(
            l10n.dictionaryCsvPreviewIntro,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: WpSpacing.md),
          Text(
            key: const ValueKey('dictionary-csv-preview-summary'),
            l10n.dictionaryCsvSummaryLine(
              plan.count(ReplacementImportStatus.added),
              plan.count(ReplacementImportStatus.duplicate),
              plan.conflictCount,
              plan.count(ReplacementImportStatus.circular),
              widget.result.errors.length,
            ),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: WpSpacing.md),
          if (neverFiresCount > 0) ...[
            WpBanner(
              key: const ValueKey('dictionary-csv-preview-never-fires'),
              tone: WpBannerTone.warning,
              message: l10n.dictionaryCsvNeverFiresCount(neverFiresCount),
            ),
            const SizedBox(height: WpSpacing.md),
          ],
          if (plan.count(ReplacementImportStatus.duplicate) ==
                  widget.result.rows.length &&
              widget.result.rows.isNotEmpty) ...[
            WpBanner(
              key: const ValueKey('dictionary-csv-preview-all-present'),
              tone: WpBannerTone.info,
              message: l10n.dictionaryCsvAllPresent,
            ),
            const SizedBox(height: WpSpacing.md),
          ],
          if (widget.result.truncated) ...[
            WpBanner(
              tone: WpBannerTone.info,
              message: l10n.dictionaryCsvTruncated(replacementCsvMaxRows),
            ),
            const SizedBox(height: WpSpacing.md),
          ],
          Text(
            l10n.dictionaryCsvStrategyLabel,
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: WpSpacing.xs),
          WpSegmentedSelector(
            key: const ValueKey('dictionary-csv-preview-strategy'),
            borderColor: WpColors.borderSubtle,
            surfaceColor: WpColors.cardFill,
            textSecondary: WpColors.textMuted,
            items: [
              for (final option in ReplacementImportStrategy.values)
                WpSegmentItem(
                  label: _strategyLabel(l10n, option),
                  isActive: _strategy == option,
                  onTap: () => setState(() => _strategy = option),
                ),
            ],
          ),
          const SizedBox(height: WpSpacing.xs),
          Text(
            key: const ValueKey('dictionary-csv-preview-strategy-hint'),
            _strategyHint(l10n, plan),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: WpSpacing.md),
          if (widget.result.errors.isNotEmpty) ...[
            WpBanner(
              key: const ValueKey('dictionary-csv-preview-errors'),
              tone: WpBannerTone.warning,
              message: l10n.dictionaryCsvErrorSummary(
                widget.result.errors.length,
              ),
            ),
            for (final error in widget.result.errors)
              Padding(
                key: ValueKey('dictionary-csv-preview-error-${error.line}'),
                padding: const EdgeInsets.only(top: WpSpacing.xs),
                child: Text(
                  l10n.dictionaryCsvLineError(
                    error.line,
                    _reasonText(l10n, error.reason),
                  ),
                ),
              ),
            const SizedBox(height: WpSpacing.md),
          ],
          for (var i = 0; i < widget.result.rows.length; i++) ...[
            _PreviewRow(
              key: ValueKey('dictionary-csv-preview-row-$i'),
              statusKey: ValueKey('dictionary-csv-preview-row-status-$i'),
              checkboxKey: ValueKey('dictionary-csv-preview-select-$i'),
              row: widget.result.rows[i],
              ticked: !_unticked.contains(i),
              onToggle: all.statuses[i] == ReplacementImportStatus.added
                  ? () => setState(() {
                      if (!_unticked.remove(i)) _unticked.add(i);
                    })
                  : null,
              statusText: statusByRow.containsKey(i)
                  ? _statusText(l10n, statusByRow[i]!)
                  : l10n.dictionaryCsvRowWillAdd,
            ),
            if (i < widget.result.rows.length - 1) const Divider(height: 1),
          ],
          const SizedBox(height: WpSpacing.lg),
          WpButton(
            key: const ValueKey('dictionary-csv-preview-import'),
            label: l10n.dictionaryCsvPreviewAddCount(plan.writeCount),
            variant: WpButtonVariant.primary,
            onPressed: plan.writeCount == 0
                ? null
                : () => Navigator.of(context).pop(plan),
          ),
        ],
      ),
    );
  }

  String _packageHeader(BuildContext context, L10n l10n) {
    final meta = widget.result.meta;
    if (meta == null) return l10n.dictionaryCsvPackageNone;
    final created = meta.created;
    final date = created == null
        ? '-'
        : MaterialLocalizations.of(context).formatShortDate(created);
    return l10n.dictionaryCsvPackageHeader(meta.name ?? '-', date);
  }

  static String _strategyLabel(
    L10n l10n,
    ReplacementImportStrategy strategy,
  ) => switch (strategy) {
    ReplacementImportStrategy.skip => l10n.dictionaryCsvStrategySkip,
    ReplacementImportStrategy.overwrite => l10n.dictionaryCsvStrategyOverwrite,
    ReplacementImportStrategy.keepBoth => l10n.dictionaryCsvStrategyKeepBoth,
  };

  String _strategyHint(L10n l10n, ReplacementImportPlan plan) =>
      switch (_strategy) {
        ReplacementImportStrategy.skip => l10n.dictionaryCsvStrategySkipHint,
        ReplacementImportStrategy.overwrite =>
          l10n.dictionaryCsvStrategyOverwriteHint(plan.changedExistingCount),
        ReplacementImportStrategy.keepBoth =>
          l10n.dictionaryCsvStrategyKeepBothHint,
      };

  static String _statusText(L10n l10n, ReplacementImportStatus status) {
    final texts = {
      ReplacementImportStatus.added: l10n.dictionaryCsvStatusAdded,
      ReplacementImportStatus.duplicate: l10n.dictionaryCsvStatusDuplicate,
      ReplacementImportStatus.conflictSkipped:
          l10n.dictionaryCsvStatusConflictSkipped,
      ReplacementImportStatus.conflictReplaced:
          l10n.dictionaryCsvStatusConflictReplaced,
      ReplacementImportStatus.conflictKept:
          l10n.dictionaryCsvStatusConflictKept,
      ReplacementImportStatus.supersededInFile:
          l10n.dictionaryCsvStatusSuperseded,
      ReplacementImportStatus.circular: l10n.dictionaryCsvStatusCircular,
    };
    return texts[status]!;
  }

  String _reasonText(L10n l10n, ReplacementCsvErrorReason reason) {
    final texts = {
      ReplacementCsvErrorReason.missingFields:
          l10n.dictionaryCsvReasonMissingFields,
      ReplacementCsvErrorReason.emptyTrigger:
          l10n.dictionaryCsvReasonEmptyTrigger,
      ReplacementCsvErrorReason.triggerTooLong:
          l10n.dictionaryCsvReasonTriggerTooLong,
      ReplacementCsvErrorReason.emptyReplacement:
          l10n.dictionaryCsvReasonEmptyReplacement,
      ReplacementCsvErrorReason.replacementTooLong:
          l10n.dictionaryCsvReasonReplacementTooLong,
      ReplacementCsvErrorReason.unknownMatchMode:
          l10n.dictionaryCsvReasonUnknownMatchMode,
      ReplacementCsvErrorReason.invalidThreshold:
          l10n.dictionaryCsvReasonInvalidThreshold,
      ReplacementCsvErrorReason.tooManyTriggers: l10n
          .dictionaryCsvReasonTooManyTriggers(replacementCsvMaxTriggersPerRow),
      ReplacementCsvErrorReason.controlCharacter:
          l10n.dictionaryCsvReasonControlCharacter,
    };
    return texts[reason]!;
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({
    super.key,
    required this.statusKey,
    required this.checkboxKey,
    required this.row,
    required this.ticked,
    required this.onToggle,
    required this.statusText,
  });

  final Key statusKey;
  final Key checkboxKey;
  final ReplacementCsvRow row;
  final bool ticked;

  /// Null for rows that cannot be unticked (duplicates, conflicts).
  final VoidCallback? onToggle;
  final String statusText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = '${row.triggers.join(', ')} → ${row.replacement}';
    final toggle = onToggle;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: WpSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (toggle != null)
            WpRowCheckbox(
              key: checkboxKey,
              value: ticked,
              onChanged: toggle,
              semanticsLabel: text,
            )
          else
            const SizedBox(width: WpRowCheckbox.extent),
          Expanded(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: ticked
                  ? theme.textTheme.bodyMedium
                  : theme.textTheme.bodyMedium?.copyWith(
                      decoration: TextDecoration.lineThrough,
                    ),
            ),
          ),
          const SizedBox(width: WpSpacing.sm),
          Text(key: statusKey, statusText, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
