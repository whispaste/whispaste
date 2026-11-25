/// Review page between a snippet file and the library (#665). Shows the
/// counts for the chosen conflict strategy, every entry with its status, and
/// the entries that could not be read. The plan shown here is the plan that
/// gets written, and nothing is written until the user confirms.
library;

import 'package:flutter/material.dart';

import '../../core/l10n/generated/app_localizations.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../services/snippets/snippet_file.dart';
import '../../widgets/page_shell.dart';
import '../../widgets/wp_banner.dart';
import '../../widgets/wp_button.dart';
import '../../widgets/wp_page_header.dart';
import '../../widgets/wp_row_divider.dart';
import '../../widgets/wp_segmented_selector.dart';

class SnippetImportPreviewPage extends StatefulWidget {
  const SnippetImportPreviewPage({
    super.key,
    required this.result,
    required this.existing,
  });

  final SnippetFileParseResult result;

  /// The active snippets, as the planner needs them. The trash stays out.
  final List<SnippetImportExisting> existing;

  @override
  State<SnippetImportPreviewPage> createState() =>
      _SnippetImportPreviewPageState();
}

class _SnippetImportPreviewPageState extends State<SnippetImportPreviewPage> {
  SnippetConflictStrategy _strategy = SnippetConflictStrategy.skip;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final entries = widget.result.entries;
    final errors = widget.result.errors;
    final plan = planSnippetImport(
      entries,
      widget.existing,
      strategy: _strategy,
    );

    return Scaffold(
      body: WpPageShell(
        scrollable: false,
        bodyPadding: EdgeInsets.zero,
        header: WpPageHeader(
          title: l10n.snippetsImportPreviewTitle,
          trailing: WpButton(
            testId: 'snippets-import-preview-close',
            label: l10n.actionClose,
            variant: WpButtonVariant.ghost,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            WpPageFrame.inset,
            WpPageFrame.titleToContent,
            WpPageFrame.inset,
            WpPageFrame.bottom,
          ),
          children: [
            Text(
              l10n.snippetsImportPreviewIntro,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: WpSpacing.md),
            Text(
              key: const ValueKey('snippets-import-preview-summary'),
              l10n.snippetsImportSummaryLine(
                plan.count(SnippetImportStatus.added),
                plan.count(SnippetImportStatus.duplicate),
                plan.conflictCount,
                errors.length,
              ),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: WpSpacing.md),
            if (entries.isNotEmpty &&
                plan.count(SnippetImportStatus.duplicate) ==
                    entries.length) ...[
              WpBanner(
                key: const ValueKey('snippets-import-preview-all-present'),
                tone: WpBannerTone.info,
                message: l10n.snippetsImportAllPresent,
              ),
              const SizedBox(height: WpSpacing.md),
            ],
            if (widget.result.truncated) ...[
              WpBanner(
                key: const ValueKey('snippets-import-preview-truncated'),
                tone: WpBannerTone.info,
                message: l10n.snippetsImportTruncated(snippetFileMaxEntries),
              ),
              const SizedBox(height: WpSpacing.md),
            ],
            Text(
              l10n.snippetsImportStrategyLabel,
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(height: WpSpacing.xs),
            WpSegmentedSelector(
              key: const ValueKey('snippets-import-preview-strategy'),
              borderColor: WpColors.borderSubtle,
              surfaceColor: WpColors.cardFill,
              textSecondary: WpColors.textMuted,
              items: [
                for (final option in SnippetConflictStrategy.values)
                  WpSegmentItem(
                    label: _strategyLabel(l10n, option),
                    isActive: _strategy == option,
                    onTap: () => setState(() => _strategy = option),
                    testId: 'snippets-import-preview-strategy-${option.name}',
                  ),
              ],
            ),
            const SizedBox(height: WpSpacing.xs),
            Text(
              key: const ValueKey('snippets-import-preview-strategy-hint'),
              _strategyHint(l10n, plan),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: WpSpacing.md),
            if (errors.isNotEmpty) ...[
              WpBanner(
                key: const ValueKey('snippets-import-preview-errors'),
                tone: WpBannerTone.warning,
                message: l10n.snippetsImportErrorSummary(errors.length),
              ),
              for (final error in errors)
                Padding(
                  key: ValueKey(
                    'snippets-import-preview-error-${error.position}',
                  ),
                  padding: const EdgeInsets.only(top: WpSpacing.xs),
                  child: Text(_errorText(l10n, error)),
                ),
              const SizedBox(height: WpSpacing.md),
            ],
            for (var i = 0; i < plan.rows.length; i++) ...[
              _PreviewRow(
                key: ValueKey('snippets-import-preview-row-$i'),
                statusKey: ValueKey('snippets-import-preview-row-status-$i'),
                title: plan.rows[i].entry.title,
                statusText: _statusText(l10n, plan.rows[i]),
              ),
              if (i < plan.rows.length - 1) const WpRowDivider(),
            ],
            const SizedBox(height: WpSpacing.lg),
            WpButton(
              testId: 'snippets-import-preview-confirm',
              label: l10n.snippetsImportConfirm(plan.writeCount),
              variant: WpButtonVariant.primary,
              onPressed: plan.writeCount == 0
                  ? null
                  : () => Navigator.of(context).pop(plan),
            ),
          ],
        ),
      ),
    );
  }

  static String _strategyLabel(L10n l10n, SnippetConflictStrategy s) =>
      switch (s) {
        SnippetConflictStrategy.skip => l10n.snippetsImportStrategySkip,
        SnippetConflictStrategy.overwrite =>
          l10n.snippetsImportStrategyOverwrite,
        SnippetConflictStrategy.keepBoth => l10n.snippetsImportStrategyKeepBoth,
      };

  String _strategyHint(L10n l10n, SnippetImportPlan plan) =>
      switch (_strategy) {
        SnippetConflictStrategy.skip => l10n.snippetsImportStrategySkipHint,
        SnippetConflictStrategy.overwrite =>
          l10n.snippetsImportStrategyOverwriteHint(
            plan.count(SnippetImportStatus.conflictReplaced),
          ),
        SnippetConflictStrategy.keepBoth =>
          l10n.snippetsImportStrategyKeepBothHint,
      };

  static String _statusText(L10n l10n, SnippetImportPlanRow row) =>
      switch (row.status) {
        SnippetImportStatus.added => l10n.snippetsImportStatusAdded,
        SnippetImportStatus.duplicate => l10n.snippetsImportStatusDuplicate,
        SnippetImportStatus.conflictSkipped =>
          l10n.snippetsImportStatusConflictSkipped,
        SnippetImportStatus.conflictReplaced =>
          l10n.snippetsImportStatusConflictReplaced,
        SnippetImportStatus.conflictKept =>
          l10n.snippetsImportStatusConflictKept(row.finalTitle),
        SnippetImportStatus.supersededInFile =>
          l10n.snippetsImportStatusSuperseded,
      };

  static String _errorText(L10n l10n, SnippetFileError error) {
    final reason = switch (error.reason) {
      SnippetFileErrorReason.malformed => l10n.snippetsImportReasonMalformed,
      SnippetFileErrorReason.missingTitle =>
        l10n.snippetsImportReasonMissingTitle,
      SnippetFileErrorReason.emptyBody => l10n.snippetsImportReasonEmptyBody,
      SnippetFileErrorReason.unknownKind =>
        l10n.snippetsImportReasonUnknownKind,
      SnippetFileErrorReason.invalidFields =>
        l10n.snippetsImportReasonInvalidFields,
    };
    final title = error.title;
    final text = l10n.snippetsImportEntryError(error.position, reason);
    return title == null || title.isEmpty ? text : '$text ($title)';
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({
    super.key,
    required this.statusKey,
    required this.title,
    required this.statusText,
  });

  final Key statusKey;
  final String title;
  final String statusText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // One announcement per row for screen readers: title and status.
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: WpSpacing.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            const SizedBox(width: WpSpacing.sm),
            Flexible(
              child: Text(
                key: statusKey,
                statusText,
                textAlign: TextAlign.end,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
