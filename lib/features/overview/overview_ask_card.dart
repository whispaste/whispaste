import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/app_urls.dart' show websiteHomeUrl;
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/logging/app_logger.dart';
import '../../core/navigation/help_target.dart';
import '../../core/navigation/page_state.dart';
import '../../core/overview/overview_logic.dart';
import '../../core/recording/recording_state.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../services/deploy_channel_service.dart';
import '../../services/review_prompt_service.dart';
import '../../services/prompt_display_arbiter.dart';
import '../../services/support_prompt_service.dart';
import '../../widgets/wp_button.dart';
import '../../widgets/wp_card.dart';
import '../../widgets/wp_icon_button.dart';
import '../settings/sections/review_support_section.dart'
    show openRateDestination;
import 'overview_header.dart' show overviewStatusIssueProvider;
import 'overview_providers.dart';
import '../../widgets/wp_copy_feedback.dart';

/// The milestone, rate/share or support card of this visit, or null. It
/// follows a good moment only: [overviewAskCard] holds the rules, the review
/// and support prompt services decide when their ask is due.
final overviewAskCardProvider = Provider.autoDispose<OverviewAskCard?>((ref) {
  final prefs = ref.watch(overviewPrefsProvider);
  if (!prefs.loaded) return null;
  final total = ref.watch(overviewDictationTotalProvider).value;
  if (total == null) return null;
  final day = prefs.askCardDay;
  final support = ref.watch(supportPromptProvider);
  return overviewAskCard(
    dictations: total,
    milestonesSeen: prefs.milestonesSeen,
    rateDue: ref.watch(reviewPromptProvider).shouldShowPrompt,
    problemShown: ref.watch(overviewStatusIssueProvider) != null,
    anyCardShownOn: day == null ? null : DateTime.tryParse(day),
    now: clock.now(),
    supportDue: support.shouldShowPrompt,
    supportRecurring: support.kind == SupportPromptKind.recurringFollowUp,
    dictationRunning: isDictationBusy(ref.watch(recordingPhaseProvider)),
  );
});

/// The quiet card in the hint place after a milestone or, later, the ask to
/// rate, share or support WhisPaste. No reward, no pressure: "Später" waits,
/// the close button stops asking.
class OverviewAskCardView extends ConsumerWidget {
  const OverviewAskCardView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (ref.watch(overviewAskCardProvider)) {
      final OverviewMilestoneCard m => _Milestone(count: m.count),
      OverviewRateShareCard() => const _ArbitratedReview(),
      final OverviewSupportCard s => _ArbitratedSupport(recurring: s.recurring),
      null => const SizedBox.shrink(),
    };
  }
}

/// Claims only when the review surface is mounted, not when it becomes due.
/// Navigating away or a hotkey cancels without persisting a snooze.
class _ArbitratedReview extends ConsumerStatefulWidget {
  const _ArbitratedReview();

  @override
  ConsumerState<_ArbitratedReview> createState() => _ArbitratedReviewState();
}

class _ArbitratedReviewState extends ConsumerState<_ArbitratedReview> {
  late final PromptDisplayArbiter _arbiter;
  late bool _claimed;

  @override
  void initState() {
    super.initState();
    _arbiter = ref.read(promptDisplayArbiterProvider);
    _claimed = _arbiter.tryClaim(PromptOwner.review, close: _cancel);
  }

  void _cancel() {
    if (!mounted || !_claimed) return;
    setState(() => _claimed = false);
    _arbiter.release(PromptOwner.review);
  }

  @override
  void dispose() {
    if (_claimed) _arbiter.release(PromptOwner.review);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_claimed) return const SizedBox.shrink();
    return ref.watch(reviewSurfaceProvider) == ReviewSurface.systemDialog
        ? const _SystemReview()
        : const _RateShare();
  }
}

class _Milestone extends ConsumerWidget {
  const _Milestone({required this.count});

  final int count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    return WpCard(
      key: const ValueKey('overview-milestone'),
      title: l10n.overviewMilestoneTitle(count),
      trailing: WpIconButton.ghost(
        testId: 'overview-milestone-close',
        icon: LucideIcons.x,
        tooltip: l10n.overviewMilestoneClose,
        onPressed: () => ref
            .read(overviewPrefsProvider.notifier)
            .closeMilestone(count, now: clock.now()),
      ),
      child: Text(l10n.overviewMilestoneBody, style: WpTextStyles.rowNote),
    );
  }
}

class _RateShare extends ConsumerWidget {
  const _RateShare();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final channel = ref.watch(deployChannelProvider);
    final notifier = ref.read(reviewPromptProvider.notifier);
    return WpCard(
      key: const ValueKey('overview-rate-share'),
      title: l10n.overviewRateTitle,
      trailing: WpIconButton.ghost(
        testId: 'overview-rate-never',
        icon: LucideIcons.x,
        tooltip: l10n.overviewAskNever,
        onPressed: () {
          unawaited(notifier.dismiss(permanent: true));
          _noteAnswered(ref);
        },
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.overviewRateBody, style: WpTextStyles.rowNote),
          const SizedBox(height: WpSpacing.sm),
          Wrap(
            spacing: WpSpacing.xs,
            runSpacing: WpSpacing.xs,
            children: [
              WpButton(
                testId: 'overview-rate',
                label: channel == DeployChannel.store
                    ? l10n.overviewRateStore
                    : l10n.overviewRateGitHub,
                variant: WpButtonVariant.secondary,
                size: WpButtonSize.dense,
                onPressed: () async {
                  _noteAnswered(ref);
                  await notifier.markShown();
                  await openRateDestination(channel);
                },
              ),
              WpCopyButton(
                testId: 'overview-share',
                label: l10n.overviewShareCopyLink,
                variant: WpButtonVariant.secondary,
                size: WpButtonSize.dense,
                icon: null,
                // The website link only: no text, no recording, nothing personal.
                text: () => websiteHomeUrl(
                  Localizations.localeOf(context).languageCode,
                ),
                onCopied: () {
                  _noteAnswered(ref);
                  unawaited(notifier.markShown());
                },
              ),
              WpButton(
                testId: 'overview-rate-later',
                label: l10n.overviewAskLater,
                variant: WpButtonVariant.ghost,
                size: WpButtonSize.dense,
                onPressed: () {
                  unawaited(notifier.dismiss(permanent: false));
                  _noteAnswered(ref);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// An answered rate/share or support card keeps the place quiet for the rest
/// of the day, so the next ask never follows on the same day.
void _noteAnswered(WidgetRef ref) => unawaited(
  ref.read(overviewPrefsProvider.notifier).noteAskCardDay(clock.now()),
);

/// The support ask as a quiet card (#1094): never a dialog, no focus change.
/// It claims the shared display window only while mounted; a hotkey or
/// navigating away hides it without answering it. The round is counted once
/// the card is painted.
class _ArbitratedSupport extends ConsumerStatefulWidget {
  const _ArbitratedSupport({required this.recurring});

  final bool recurring;

  @override
  ConsumerState<_ArbitratedSupport> createState() => _ArbitratedSupportState();
}

class _ArbitratedSupportState extends ConsumerState<_ArbitratedSupport> {
  late final PromptDisplayArbiter _arbiter;
  late bool _claimed;

  @override
  void initState() {
    super.initState();
    _arbiter = ref.read(promptDisplayArbiterProvider);
    _claimed = _arbiter.tryClaim(PromptOwner.support, close: _cancel);
    if (_claimed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _claimed) {
          unawaited(ref.read(supportPromptProvider.notifier).markPresented());
        }
      });
    }
  }

  void _cancel() {
    if (!mounted || !_claimed) return;
    setState(() => _claimed = false);
    _arbiter.release(PromptOwner.support);
  }

  @override
  void dispose() {
    if (_claimed) _arbiter.release(PromptOwner.support);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_claimed) return const SizedBox.shrink();
    final l10n = L10n.of(context);
    final notifier = ref.read(supportPromptProvider.notifier);
    return WpCard(
      key: const ValueKey('overview-support'),
      titleTestId: 'overview-support',
      title: widget.recurring
          ? l10n.overviewSupportRecurringTitle
          : l10n.overviewSupportTitle,
      trailing: WpIconButton.ghost(
        testId: 'overview-support-never',
        icon: LucideIcons.x,
        tooltip: l10n.overviewAskNever,
        onPressed: () {
          unawaited(notifier.never());
          _noteAnswered(ref);
        },
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.recurring
                ? l10n.overviewSupportRecurringBody
                : l10n.overviewSupportBody,
            style: WpTextStyles.rowNote,
          ),
          const SizedBox(height: WpSpacing.sm),
          Wrap(
            spacing: WpSpacing.buttonGap,
            runSpacing: WpSpacing.xs,
            children: [
              WpButton(
                testId: 'overview-support-open',
                label: l10n.overviewSupportAction,
                variant: WpButtonVariant.secondary,
                size: WpButtonSize.dense,
                onPressed: () {
                  unawaited(notifier.opened());
                  _noteAnswered(ref);
                  ref
                      .read(helpTargetProvider.notifier)
                      .set(const HelpTarget(tab: HelpTab.support));
                  ref.read(activePageProvider.notifier).setPage('help');
                },
              ),
              WpButton(
                testId: 'overview-support-later',
                label: l10n.overviewAskLater,
                variant: WpButtonVariant.ghost,
                size: WpButtonSize.dense,
                onPressed: () {
                  unawaited(notifier.dismiss());
                  _noteAnswered(ref);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Mac App Store build: no own card. When the ask is due the system rating
/// dialog is requested once; the prompt service then counts it as shown, so
/// its cooldowns apply on top of StoreKit's own three-per-365-days cap.
final _log = AppLogger('SystemReview');

class _SystemReview extends ConsumerStatefulWidget {
  const _SystemReview();

  @override
  ConsumerState<_SystemReview> createState() => _SystemReviewState();
}

class _SystemReviewState extends ConsumerState<_SystemReview> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_ask()));
  }

  Future<void> _ask() async {
    if (!mounted) return;
    final request = ref.read(systemReviewRequesterProvider);
    final notifier = ref.read(reviewPromptProvider.notifier);
    try {
      await request();
    } on Exception catch (e) {
      // No dialog available: still count it, so the ask does not loop.
      _log.warning('system review request failed: $e');
    }
    if (mounted) _noteAnswered(ref);
    await notifier.markShown();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
