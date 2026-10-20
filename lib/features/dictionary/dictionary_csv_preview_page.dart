/// Review page between a CSV file and the replacement list. Shows what will
/// be added, which rows are skipped as duplicates, and the lines that could
/// not be read. Nothing is written until the user confirms.
library;

import 'package:flutter/material.dart';

import '../../core/l10n/generated/app_localizations.dart';
import '../../core/theme/tokens.dart';
import '../../services/dictionary/replacement_csv.dart';
import '../../services/dictionary/replacement_duplicates.dart';
import '../../widgets/wp_banner.dart';
import '../../widgets/wp_button.dart';
import '../../widgets/wp_row_checkbox.dart';

class DictionaryCsvPreviewPage extends StatefulWidget {
  const DictionaryCsvPreviewPage({
    super.key,
    required this.result,
    this.existingTriggerKeys = const {},
  });

  final ReplacementCsvParseResult result;

  /// Normalized trigger keys already in the list. A row that uses one of them
  /// (or one used by an earlier row of the same file) is skipped.
  final Set<String> existingTriggerKeys;

  @override
  State<DictionaryCsvPreviewPage> createState() =>
      _DictionaryCsvPreviewPageState();
}

class _DictionaryCsvPreviewPageState extends State<DictionaryCsvPreviewPage> {
  /// Indices of rows the user unticked. Duplicates are never importable, so
  /// they have no box and are not in this set.
  final Set<int> _unticked = {};

  ReplacementCsvParseResult get result => widget.result;
  Set<String> get existingTriggerKeys => widget.existingTriggerKeys;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final decisions = _decide(result.rows, existingTriggerKeys);
    final toAdd = [
      for (var i = 0; i < decisions.length; i++)
        if (!decisions[i].skipped && !_unticked.contains(i)) decisions[i].row,
    ];
    final skippedCount = decisions.length - toAdd.length;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.dictionaryCsvPreviewTitle)),
      body: ListView(
        padding: const EdgeInsets.all(WpSpacing.lg),
        children: [
          Text(
            l10n.dictionaryCsvPreviewIntro,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: WpSpacing.md),
          if (result.truncated) ...[
            WpBanner(
              tone: WpBannerTone.info,
              message: l10n.dictionaryCsvTruncated(replacementCsvMaxRows),
            ),
            const SizedBox(height: WpSpacing.md),
          ],
          if (skippedCount > 0) ...[
            WpBanner(
              key: const ValueKey('dictionary-csv-preview-duplicates'),
              tone: WpBannerTone.info,
              message: l10n.dictionaryCsvSkippedDuplicates(skippedCount),
            ),
            const SizedBox(height: WpSpacing.md),
          ],
          if (result.errors.isNotEmpty) ...[
            WpBanner(
              key: const ValueKey('dictionary-csv-preview-errors'),
              tone: WpBannerTone.warning,
              message: l10n.dictionaryCsvErrorSummary(result.errors.length),
            ),
            for (final error in result.errors)
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
          for (var i = 0; i < decisions.length; i++) ...[
            _PreviewRow(
              key: ValueKey('dictionary-csv-preview-row-$i'),
              statusKey: ValueKey('dictionary-csv-preview-row-status-$i'),
              decision: decisions[i],
              ticked: !_unticked.contains(i),
              onToggle: decisions[i].skipped
                  ? null
                  : () => setState(() {
                      if (!_unticked.remove(i)) _unticked.add(i);
                    }),
              checkboxKey: ValueKey('dictionary-csv-preview-select-$i'),
              willAddLabel: l10n.dictionaryCsvRowWillAdd,
              skippedLabel: l10n.dictionaryCsvRowSkipped,
            ),
            if (i < decisions.length - 1) const Divider(height: 1),
          ],
          const SizedBox(height: WpSpacing.lg),
          WpButton(
            key: const ValueKey('dictionary-csv-preview-import'),
            label: l10n.dictionaryCsvPreviewAddCount(toAdd.length),
            variant: WpButtonVariant.primary,
            onPressed: toAdd.isEmpty
                ? null
                : () => Navigator.of(context).pop(toAdd),
          ),
        ],
      ),
    );
  }

  static List<_RowDecision> _decide(
    List<ReplacementCsvRow> rows,
    Set<String> existing,
  ) {
    final seen = <String>{...existing};
    final out = <_RowDecision>[];
    for (final row in rows) {
      final keys = [for (final t in row.triggers) normalizeTriggerKey(t)];
      final skipped = keys.any(seen.contains);
      seen.addAll(keys);
      out.add(_RowDecision(row, skipped));
    }
    return out;
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
    };
    return texts[reason]!;
  }
}

class _RowDecision {
  const _RowDecision(this.row, this.skipped);

  final ReplacementCsvRow row;
  final bool skipped;
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({
    super.key,
    required this.statusKey,
    required this.decision,
    required this.ticked,
    required this.onToggle,
    required this.checkboxKey,
    required this.willAddLabel,
    required this.skippedLabel,
  });

  final Key statusKey;
  final _RowDecision decision;
  final bool ticked;

  /// Null for duplicates, which are skipped and cannot be selected.
  final VoidCallback? onToggle;
  final Key checkboxKey;
  final String willAddLabel;
  final String skippedLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final row = decision.row;
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
              style: decision.skipped
                  ? theme.textTheme.bodyMedium?.copyWith(
                      decoration: TextDecoration.lineThrough,
                    )
                  : theme.textTheme.bodyMedium,
            ),
          ),
          const SizedBox(width: WpSpacing.sm),
          Text(
            key: statusKey,
            decision.skipped ? skippedLabel : willAddLabel,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
