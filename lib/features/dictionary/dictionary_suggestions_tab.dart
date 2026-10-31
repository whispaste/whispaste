/// Suggestions tab: correction learning switch and the candidates waiting for
/// a decision. Each candidate is decided on its own; a rejected candidate is
/// shown and not selected, which is the existing reject signal of
/// `CorrectionLearningService.commit`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/config/settings_provider.dart';
import '../../core/data/database.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/theme/tokens.dart';
import '../../services/replacements/correction_candidate_detector.dart';
import '../../services/replacements/correction_learning_service.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/toast.dart';
import '../../widgets/wp_banner.dart';
import '../../widgets/wp_button.dart';
import '../../widgets/wp_error_notice.dart';
import '../replacements/correction_cards.dart';
import '../replacements/replacements_page.dart';

class DictionarySuggestionsTab extends ConsumerStatefulWidget {
  const DictionarySuggestionsTab({super.key});

  @override
  ConsumerState<DictionarySuggestionsTab> createState() =>
      _DictionarySuggestionsTabState();
}

class _DictionarySuggestionsTabState
    extends ConsumerState<DictionarySuggestionsTab> {
  /// Candidates whose accept/reject is still being saved. Their buttons are
  /// disabled so a second tap cannot decide the same suggestion twice.
  final _deciding = <String>{};

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final enabled =
        ref.watch(
          settingsProvider.select(
            (s) => s.value?.behavior.correctionLearningEnabled,
          ),
        ) ??
        true;
    final candidates = ref.watch(pendingCorrectionCandidatesProvider);
    final items = candidates.value ?? const <CorrectionCandidate>[];

    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: WpSpacing.xl,
        vertical: WpSpacing.lg,
      ),
      children: [
        CorrectionLearningToggleCard(
          enabled: enabled,
          onChanged: (v) => ref
              .read(settingsProvider.notifier)
              .updateSettings(
                (s) => s.copyWithSections(
                  behavior: s.behavior.copyWith(correctionLearningEnabled: v),
                ),
              ),
        ),
        const SizedBox(height: WpSpacing.md),
        WpBanner(
          tone: WpBannerTone.info,
          message: l10n.dictionarySuggestionsHint(correctionCandidateThreshold),
        ),
        const SizedBox(height: WpSpacing.md),
        // A failed load is not "no suggestions": say so (UIA-DIC-02).
        if (candidates.hasError)
          WpErrorNotice(cause: l10n.errorGeneric)
        else if (items.isEmpty)
          WpEmptyState(
            icon: LucideIcons.sparkles,
            title: l10n.dictionarySuggestionsEmpty,
            hint: l10n.dictionarySuggestionsEmptyHint,
          )
        else
          Column(
            key: const ValueKey('dictionary-suggestions-list'),
            children: [
              for (final c in items)
                _SuggestionRow(
                  candidate: c,
                  busy: _deciding.contains(c.id),
                  onAccept: () => _decide(context, c, accept: true),
                  onReject: () => _decide(context, c, accept: false),
                ),
            ],
          ),
      ],
    );
  }

  Future<void> _decide(
    BuildContext context,
    CorrectionCandidate candidate, {
    required bool accept,
  }) async {
    if (_deciding.contains(candidate.id)) return;
    setState(() => _deciding.add(candidate.id));
    try {
      final l10n = L10n.of(context);
      final service = ref.read(correctionLearningServiceProvider);
      final db = ref.read(historyDatabaseProvider);
      await service.commit(
        shownIds: [candidate.id],
        acceptedIds: accept ? [candidate.id] : const [],
        db: db,
      );
      ref.invalidate(pendingCorrectionCandidatesProvider);
      if (accept) await ref.read(replacementsProvider.notifier).reload();
      if (!context.mounted) return;
      WpToast.show(
        context,
        message: accept
            ? l10n.dictionarySuggestionAccepted
            : l10n.dictionarySuggestionRejected,
        type: WpToastType.success,
      );
    } finally {
      if (mounted) setState(() => _deciding.remove(candidate.id));
    }
  }
}

class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({
    required this.candidate,
    required this.busy,
    required this.onAccept,
    required this.onReject,
  });

  final CorrectionCandidate candidate;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: WpSpacing.xs),
          child: Row(
            children: [
              Expanded(child: Text(candidate.displayText)),
              WpButton(
                key: ValueKey('dictionary-suggestion-reject-${candidate.id}'),
                label: l10n.dictionarySuggestionReject,
                variant: WpButtonVariant.ghost,
                onPressed: busy ? null : onReject,
              ),
              WpButton(
                key: ValueKey('dictionary-suggestion-accept-${candidate.id}'),
                label: l10n.dictionarySuggestionAccept,
                variant: WpButtonVariant.primary,
                onPressed: busy ? null : onAccept,
              ),
            ],
          ),
        ),
        const Divider(height: 1, indent: WpSpacing.xs),
      ],
    );
  }
}
