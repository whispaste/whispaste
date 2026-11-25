/// Suggestions tab: correction learning switch and the candidates waiting for
/// a decision. Each candidate is decided on its own, in one of three ways: as
/// a replacement, as a vocabulary term, or rejected for good. Nothing is
/// applied before one of these choices.
///
/// The rows carry no filled primary button: every row is an equal decision,
/// and a filled button per row would make the list shout N times (#321). A
/// rejection is undone from the notice it leaves, not asked about beforehand:
/// rejecting is routine, and the row comes back with one click.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/config/settings_provider.dart';
import '../../core/data/database.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/logging/app_logger.dart';
import '../../core/navigation/page_state.dart';
import '../../core/theme/tokens.dart';
import '../../services/replacements/correction_candidate_detector.dart';
import '../../services/replacements/correction_learning_service.dart';
import '../../services/replacements/learn_correction_hotkey.dart';
import '../../services/replacements/target_field_learning.dart'
    show masCorrectionHintVisible;
import '../../widgets/empty_state.dart';
import '../../widgets/wp_list_tile_surface.dart';
import '../../core/accessibility/announce.dart';
import '../../widgets/wp_page_notice.dart';
import '../../widgets/wp_notice_bar.dart';
import '../../widgets/wp_banner.dart';
import '../../widgets/wp_button.dart';
import '../../widgets/wp_error_notice.dart';
import '../../widgets/wp_list_skeleton.dart';
import '../replacements/correction_cards.dart';
import '../replacements/replacements_page.dart';
import 'correction_learning_log.dart';
import 'dictionary_notice.dart';
import 'term_store.dart';
import '../../widgets/page_shell.dart' show WpPageFrame;

final _log = AppLogger('DictionarySuggestionsTab');

/// Height of one suggestion row (text, gap, button line, padding, divider) at
/// the default text size, so the loading bars reserve the rows' space.
const double _suggestionRowHeight = 93;

class DictionarySuggestionsTab extends ConsumerStatefulWidget {
  const DictionarySuggestionsTab({
    super.key,
    this.embedded = false,
    this.query = '',
  });
  final bool embedded;
  final String query;

  @override
  ConsumerState<DictionarySuggestionsTab> createState() =>
      _DictionarySuggestionsTabState();
}

class _DictionarySuggestionsTabState
    extends ConsumerState<DictionarySuggestionsTab> {
  /// Candidates whose decision is still being saved. Their buttons are
  /// disabled so a second tap cannot decide the same suggestion twice.
  final _deciding = <String>{};

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    // A hotkey press in another app adds a suggestion: show it at once.
    ref.listen(learnCorrectionFeedbackProvider, (_, next) {
      if (next?.outcome == LearnCorrectionOutcome.proposed) {
        ref.invalidate(pendingCorrectionCandidatesProvider);
        ref.invalidate(correctionLogProvider);
      }
    });
    final enabled =
        ref.watch(
          settingsProvider.select(
            (s) => s.value?.behavior.correctionLearningEnabled,
          ),
        ) ??
        true;
    final candidates = ref.watch(pendingCorrectionCandidatesProvider);
    final items = (candidates.value ?? const <CorrectionCandidate>[])
        .where(
          (c) =>
              c.displayText.toLowerCase().contains(widget.query.toLowerCase()),
        )
        .toList();

    final content = ListView(
      shrinkWrap: widget.embedded,
      physics: widget.embedded ? const NeverScrollableScrollPhysics() : null,
      padding: widget.embedded
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(
              horizontal: WpPageFrame.inset,
              vertical: WpSpacing.lg,
            ),
      children: [
        if (!widget.embedded) ...[
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
            message: l10n.dictionarySuggestionsHint(
              correctionCandidateThreshold,
            ),
          ),
          const SizedBox(height: WpSpacing.md),
          // Mac App Store: other apps cannot be read, say once which ways
          // still teach WhisPaste (#934).
          if (masCorrectionHintVisible()) ...[
            WpBanner(
              key: const ValueKey('dictionary-mas-correction-hint'),
              tone: WpBannerTone.info,
              message: l10n.dictionaryMasCorrectionHint,
            ),
            const SizedBox(height: WpSpacing.md),
          ],
        ],
        if (widget.embedded && masCorrectionHintVisible())
          Text(
            l10n.dictionaryMasCorrectionHint,
            key: const ValueKey('dictionary-mas-correction-hint'),
          ),
        // A failed load is not "no suggestions": say so (UIA-DIC-02), with
        // a way to try again.
        if (candidates.hasError && !candidates.isLoading)
          WpErrorNotice(
            cause: l10n.dictionarySuggestionsLoadFailed,
            nextStep: l10n.dictionarySuggestionsLoadFailedNext,
            action: WpButton(
              testId: 'dictionary-suggestions-retry',
              label: l10n.actionRetry,
              variant: WpButtonVariant.secondary,
              onPressed: () =>
                  ref.invalidate(pendingCorrectionCandidatesProvider),
            ),
          )
        // Not loaded yet is not "no suggestions" either: the empty state
        // waits for the first result.
        else if (!candidates.hasValue)
          const WpListSkeleton(
            key: ValueKey('dictionary-suggestions-loading'),
            rowHeight: _suggestionRowHeight,
            count: 3,
            padding: EdgeInsets.zero,
            embedded: true,
          )
        else if (items.isEmpty && widget.embedded)
          Text(
            widget.query.isEmpty
                ? l10n.dictionarySuggestionsEmpty
                : l10n.searchNoMatches,
          )
        else if (items.isEmpty)
          WpEmptyState(
            icon: LucideIcons.sparkles,
            title: l10n.dictionarySuggestionsEmpty,
            hint: l10n.dictionarySuggestionsEmptyHint,
            // Suggestions come from corrections made in the recordings, so
            // the one way on leads there (#1076).
            actionLabel: l10n.firstStepsItemCopyAction,
            actionTestId: 'dictionary-suggestions-to-history',
            onAction: () =>
                ref.read(activePageProvider.notifier).setPage('history'),
          )
        else
          Column(
            key: const ValueKey('dictionary-suggestions-list'),
            children: [
              for (final c in items)
                _SuggestionRow(
                  candidate: c,
                  busy: _deciding.contains(c.id),
                  onDecide: (decision) => _decide(context, c, decision),
                ),
            ],
          ),
        if (!widget.embedded) ...[
          const SizedBox(height: WpSpacing.lg),
          const CorrectionLearningLog(),
        ],
      ],
    );
    return content;
  }

  Future<void> _decide(
    BuildContext context,
    CorrectionCandidate candidate,
    CorrectionDecision decision,
  ) async {
    if (_deciding.contains(candidate.id)) return;
    setState(() => _deciding.add(candidate.id));
    final l10n = L10n.of(context);
    try {
      final container = ProviderScope.containerOf(context, listen: false);
      var termAdded = false;
      final service = ref.read(correctionLearningServiceProvider);
      final db = ref.read(historyDatabaseProvider);
      final result = await service.commit(
        decisions: {candidate.id: decision},
        db: db,
        // The term is stored before the suggestion counts as accepted.
        // A term is the entry "term → term" (#1969); undo only removes one
        // that this decision added.
        saveTerms: (terms) async {
          termAdded = (await addDictionaryTerms(container, terms)).isNotEmpty;
        },
      );
      if (result.replacementsAdded > 0) {
        await ref.read(replacementsProvider.notifier).reload();
      }
      if (!context.mounted) return;
      if (decision == CorrectionDecision.reject) {
        _offerUndo(context, candidate);
        return;
      }
      if (decision == CorrectionDecision.term && result.terms.isNotEmpty) {
        var undoing = false;
        showWpPageNotice(
          context,
          page: dictionaryNoticePage,
          notice: WpPageNotice(
            id: 'suggestion-term-added',
            message: l10n.dictionarySuggestionAcceptedTerm,
            tone: WpBannerTone.info,
            action: (_) => WpButton(
              testId: 'dictionary-suggestion-term-undo',
              label: l10n.undo,
              variant: WpButtonVariant.ghost,
              onPressed: () async {
                if (undoing) return;
                undoing = true;
                try {
                  await service.undoTerm(
                    id: candidate.id,
                    db: db,
                    removeTerm: (term) async {
                      if (!termAdded) return;
                      await removeDictionaryTerm(container, term);
                    },
                  );
                  container
                      .read(wpPageNoticeProvider(dictionaryNoticePage).notifier)
                      .dismiss();
                } catch (_) {
                  container
                      .read(wpPageNoticeProvider(dictionaryNoticePage).notifier)
                      .show(
                        WpPageNotice(
                          id: 'suggestion-undo-failed',
                          message: l10n.dictionarySuggestionFailed,
                        ),
                      );
                } finally {
                  undoing = false;
                  container.invalidate(pendingCorrectionCandidatesProvider);
                  container.invalidate(correctionLogProvider);
                  container.invalidate(learnedTermsProvider);
                }
              },
            ),
          ),
        );
      }
      // The row leaves the list, which is the visible result; the outcome
      // is only read out.
      announce(
        View.of(context),
        decision == CorrectionDecision.term
            ? l10n.dictionarySuggestionAcceptedTerm
            : l10n.dictionarySuggestionAccepted,
        Directionality.of(context),
      );
    } catch (e, st) {
      _log.error('Deciding a correction suggestion failed', e, st);
      if (context.mounted) {
        showWpPageNotice(
          context,
          page: dictionaryNoticePage,
          notice: WpPageNotice(
            id: 'suggestion-failed',
            message: l10n.dictionarySuggestionFailed,
          ),
        );
      }
    } finally {
      // Reload in every case: the list must show what is really stored.
      ref.invalidate(pendingCorrectionCandidatesProvider);
      ref.invalidate(correctionLogProvider);
      ref.invalidate(learnedTermsProvider);
      if (mounted) setState(() => _deciding.remove(candidate.id));
    }
  }

  /// The rejected row has left the list; the notice says so and brings it
  /// back on request.
  void _offerUndo(BuildContext context, CorrectionCandidate candidate) {
    final l10n = L10n.of(context);
    // An undo stands in the notice bar at the bottom like every other
    // short confirmation, so the suggestion list keeps its place (#1903).
    showWpNotice(
      context,
      WpNotice(
        id: 'suggestion-rejected',
        kind: WpNoticeKind.undo,
        message: l10n.dictionarySuggestionRejected,
        actionLabel: l10n.dictionarySuggestionUndo,
        actionTestId: 'dictionary-suggestion-undo',
        onAction: () => _restore(context, candidate),
      ),
    );
  }

  Future<void> _restore(
    BuildContext context,
    CorrectionCandidate candidate,
  ) async {
    final l10n = L10n.of(context);
    ref.read(wpPageNoticeProvider(dictionaryNoticePage).notifier).dismiss();
    try {
      await ref
          .read(correctionLearningServiceProvider)
          .restoreRejected(candidate.id, ref.read(historyDatabaseProvider));
    } catch (e, st) {
      _log.error('Restoring a rejected correction suggestion failed', e, st);
      if (context.mounted) {
        showWpPageNotice(
          context,
          page: dictionaryNoticePage,
          notice: WpPageNotice(
            id: 'suggestion-restore-failed',
            message: l10n.dictionarySuggestionRestoreFailed,
          ),
        );
      }
    } finally {
      ref.invalidate(pendingCorrectionCandidatesProvider);
      ref.invalidate(correctionLogProvider);
    }
  }
}

class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({
    required this.candidate,
    required this.busy,
    required this.onDecide,
  });

  final CorrectionCandidate candidate;
  final bool busy;
  final ValueChanged<CorrectionDecision> onDecide;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final suggestion = '${candidate.sourceText} → ${candidate.targetText}';
    // Stretch: the row is as wide as the list, so its text and buttons start
    // at the cards' left edge instead of being centred under them.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WpListTileSurface(
          variant: WpListTileVariant.panel,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(candidate.displayText),
              const SizedBox(height: WpSpacing.xs),
              // Wrap, not a fixed Row: the decisions reflow on a narrow window
              // instead of pushing the text out of the row. The two ways to
              // keep the suggestion stay together; rejecting sits apart.
              Wrap(
                spacing: WpSpacing.lg,
                runSpacing: WpSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Wrap(
                    spacing: WpSpacing.buttonGap,
                    runSpacing: WpSpacing.xs,
                    children: [
                      Semantics(
                        identifier:
                            'dictionary-suggestion-replace-${candidate.id}',
                        child: WpButton(
                          key: ValueKey(
                            'dictionary-suggestion-replace-${candidate.id}',
                          ),
                          label: l10n.dictionarySuggestionAsReplacement,
                          semanticsLabel: l10n
                              .dictionarySuggestionReplacementA11y(suggestion),
                          variant: WpButtonVariant.secondary,
                          onPressed: busy
                              ? null
                              : () => onDecide(CorrectionDecision.replacement),
                        ),
                      ),
                      Semantics(
                        identifier:
                            'dictionary-suggestion-term-${candidate.id}',
                        child: WpButton(
                          key: ValueKey(
                            'dictionary-suggestion-term-${candidate.id}',
                          ),
                          label: l10n.dictionarySuggestionAsTerm,
                          semanticsLabel: l10n.dictionarySuggestionTermA11y(
                            suggestion,
                          ),
                          variant: WpButtonVariant.secondary,
                          tone: WpButtonTone.neutral,
                          onPressed: busy
                              ? null
                              : () => onDecide(CorrectionDecision.term),
                        ),
                      ),
                    ],
                  ),
                  Semantics(
                    identifier: 'dictionary-suggestion-reject-${candidate.id}',
                    child: WpButton(
                      key: ValueKey(
                        'dictionary-suggestion-reject-${candidate.id}',
                      ),
                      label: l10n.dictionarySuggestionReject,
                      semanticsLabel: l10n.dictionarySuggestionRejectA11y(
                        suggestion,
                      ),
                      variant: WpButtonVariant.ghost,
                      tone: WpButtonTone.neutral,
                      onPressed: busy
                          ? null
                          : () => onDecide(CorrectionDecision.reject),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
