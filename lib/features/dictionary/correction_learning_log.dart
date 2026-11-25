/// Learning log of the Suggestions tab (#383): every correction WhisPaste has
/// noticed, also those seen only once, with where it came from, how often, and
/// why it is or is not suggested. Rows can be removed one by one.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/data/database.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../services/replacements/correction_candidate_detector.dart';
import '../../services/replacements/correction_learning_service.dart';
import '../../services/replacements/correction_log.dart';
import '../../services/replacements/correction_signal.dart';
import '../../services/replacements/target_field_learning.dart';
import '../../services/replacements/target_field_span.dart';
import '../../services/app_identity/app_identity_service.dart';
import '../../widgets/section.dart';
import '../../widgets/wp_error_notice.dart';
import '../../widgets/wp_icon_button.dart';
import '../replacements/replacements_page.dart';
import '../../widgets/wp_row_divider.dart';

class CorrectionLearningLog extends ConsumerWidget {
  const CorrectionLearningLog({super.key, this.initiallyExpanded = false});
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final log = ref.watch(correctionLogProvider);
    final entries = log.value ?? const <CorrectionLogEntry>[];
    final targetApps = targetFieldStatusForLog(
      ref.watch(targetFieldStatusProvider),
    );

    return WpSection(
      testId: 'dictionary-learning-log',
      title: l10n.dictionaryLogTitle,
      subtitle: l10n.dictionaryLogSubtitle,
      collapsible: true,
      initiallyExpanded: initiallyExpanded,
      // Set apart from the list above by the section gap of the page
      // family, not glued to the last row (#1969).
      padding: const EdgeInsets.only(top: WpSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (targetApps.isNotEmpty) ...[
            _TargetAppStatusList(statuses: targetApps),
            const SizedBox(height: WpSpacing.sm),
          ],
          if (log.hasError)
            WpErrorNotice(cause: l10n.errorGeneric)
          // Nothing yet while the first load runs: "no corrections yet" would
          // be a wrong statement for the moment it takes to read the log.
          else if (!log.hasValue)
            const SizedBox.shrink()
          else if (entries.isEmpty)
            Text(
              l10n.dictionaryLogEmpty,
              key: const ValueKey('dictionary-learning-log-empty'),
              style: Theme.of(context).textTheme.bodyMedium,
            )
          else
            // One rule between two entries, none after the last (#2050).
            WpDividedColumn(
              key: const ValueKey('dictionary-learning-log-list'),
              inset: const EdgeInsetsDirectional.only(start: WpSpacing.xs),
              children: [
                for (final e in entries)
                  _LogRow(entry: e, onRemove: () => _remove(ref, e)),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _remove(WidgetRef ref, CorrectionLogEntry entry) async {
    await ref
        .read(correctionLearningServiceProvider)
        .deleteLogEntry(entry.id, ref.read(historyDatabaseProvider));
    ref.invalidate(correctionLogProvider);
    ref.invalidate(learnedTermsProvider);
    ref.invalidate(pendingCorrectionCandidatesProvider);
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.entry, required this.onRemove});

  final CorrectionLogEntry entry;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final muted = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: WpColors.textMuted);
    final seen = entry.occurrenceCount >= correctionCandidateThreshold
        ? l10n.correctionLogSeenTotal(entry.occurrenceCount)
        : l10n.correctionLogSeen(
            entry.occurrenceCount,
            correctionCandidateThreshold,
          );
    final source = switch (entry.signalSource) {
      CorrectionSignalSource.voiceCommand => l10n.correctionLogSourceVoice,
      CorrectionSignalSource.manualEdit => l10n.correctionLogSourceEdit,
      CorrectionSignalSource.targetAppEdit => l10n.correctionLogSourceTargetApp,
      CorrectionSignalSource.selectionHotkey =>
        l10n.correctionLogSourceSelectionHotkey,
    };
    final pair = '${entry.sourceText} → ${entry.targetText}';
    final date = l10n.correctionLogLastSeen(
      DateFormat.yMd(locale).add_Hm().format(entry.lastSeenAt.toLocal()),
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: WpSpacing.xs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pair,
                      key: ValueKey('dictionary-log-pair-${entry.id}'),
                    ),
                    Text(
                      '$source · $seen · $date',
                      key: ValueKey('dictionary-log-meta-${entry.id}'),
                      style: muted,
                    ),
                    Text(
                      _reasonLabel(l10n, entry.reason),
                      key: ValueKey('dictionary-log-reason-${entry.id}'),
                      style: muted,
                    ),
                  ],
                ),
              ),
              WpIconButton.ghost(
                icon: LucideIcons.x,
                tooltip: l10n.correctionLogRemove,
                semanticsLabel: l10n.correctionLogRemoveEntry(pair),
                testId: 'dictionary-log-remove-${entry.id}',
                onPressed: onRemove,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

String _reasonLabel(L10n l10n, CorrectionLogReason reason) => switch (reason) {
  CorrectionLogReason.suggested => l10n.correctionLogReasonSuggested,
  CorrectionLogReason.needsMore => l10n.correctionLogReasonNeedsMore,
  CorrectionLogReason.alreadyReplacement =>
    l10n.correctionLogReasonAlreadyReplacement,
  CorrectionLogReason.alreadyTerm => l10n.correctionLogReasonAlreadyTerm,
  CorrectionLogReason.accepted => l10n.correctionLogReasonAccepted,
  CorrectionLogReason.rejected => l10n.correctionLogReasonRejected,
};

/// Whether WhisPaste could follow edits in the last target apps (#384), or
/// why not. A reason that holds for every app (Mac App Store sandbox, missing
/// permission) is one line without an app name.
class _TargetAppStatusList extends ConsumerWidget {
  const _TargetAppStatusList({required this.statuses});

  final List<TargetFieldAppStatus> statuses;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context).textTheme;
    final muted = theme.bodySmall?.copyWith(color: WpColors.textMuted);
    return Column(
      key: const ValueKey('dictionary-log-target-apps'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.targetFieldStatusTitle, style: theme.labelLarge),
        for (final (i, s) in statuses.indexed)
          Text(
            s.app.isEmpty
                ? _targetFieldStatusText(l10n, s.reason)
                : l10n.targetFieldStatusApp(
                    ref.watch(appIdentityProvider(s.app)).value?.name ?? s.app,
                    _targetFieldStatusText(l10n, s.reason),
                  ),
            key: ValueKey('dictionary-log-target-app-$i'),
            style: muted,
          ),
      ],
    );
  }
}

String _targetFieldStatusText(
  L10n l10n,
  TargetFieldUnreadableReason? reason,
) => switch (reason) {
  null => l10n.targetFieldStatusReadable,
  TargetFieldUnreadableReason.sandbox => l10n.targetFieldReasonSandbox,
  TargetFieldUnreadableReason.permission => l10n.targetFieldReasonPermission,
  TargetFieldUnreadableReason.password => l10n.targetFieldReasonPassword,
  TargetFieldUnreadableReason.noFocus => l10n.targetFieldReasonNoFocus,
  TargetFieldUnreadableReason.noText => l10n.targetFieldReasonNoText,
  TargetFieldUnreadableReason.unsupported => l10n.targetFieldReasonUnsupported,
  TargetFieldUnreadableReason.busy ||
  TargetFieldUnreadableReason.error => l10n.targetFieldReasonError,
};
