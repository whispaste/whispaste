import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/l10n/generated/app_localizations.dart';
import '../../core/navigation/help_target.dart';
import '../../core/navigation/page_state.dart';
import '../../core/overview/overview_logic.dart';
import '../../core/recording/recording_state.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../services/prompt_display_arbiter.dart';
import '../../services/support/support_capabilities.dart';
import '../../services/support/support_state.dart';
import '../../services/support_prompt_service.dart';
import '../../widgets/wp_button.dart';
import '../../widgets/wp_card.dart';
import '../../widgets/wp_icon_button.dart';
import 'overview_header.dart' show overviewStatusIssueProvider;
import 'overview_providers.dart';

/// The milestone or support card of this visit, or null. It follows a good
/// moment only: [overviewAskCard] holds the rules, the support prompt
/// service decides when its ask is due. The rating ask is a dialog since
/// #2185 (`ReviewAskWatcher`).
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
    problemShown: ref.watch(overviewStatusIssueProvider) != null,
    anyCardShownOn: day == null ? null : DateTime.tryParse(day),
    now: clock.now(),
    supportDue: support.shouldShowPrompt,
    supportRecurring: support.kind == SupportPromptKind.recurringFollowUp,
    dictationRunning: isDictationBusy(ref.watch(recordingPhaseProvider)),
  );
});

/// The quiet card in the hint place after a milestone or, later, the ask to
/// support WhisPaste. No reward, no pressure: "Später" waits,
/// the close button stops asking.
class OverviewAskCardView extends ConsumerWidget {
  const OverviewAskCardView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (ref.watch(overviewAskCardProvider)) {
      final OverviewMilestoneCard m => _Milestone(count: m.count),
      final OverviewSupportCard s => _ArbitratedSupport(recurring: s.recurring),
      null => const SizedBox.shrink(),
    };
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

/// An answered milestone or support card keeps the place quiet for the rest
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

  /// The first ask's text. Builds that lead with the store offer get its
  /// concrete reasons for their platform (#1941); all others the general
  /// support text.
  String _initialBody(L10n l10n) {
    final namesStore = overviewNamesStoreOffer(
      ref.watch(supportCapabilitiesProvider),
      storeOfferDismissed: ref.watch(
        supportStatusProvider.select((s) => s.storeOfferDismissed),
      ),
    );
    if (!namesStore) return l10n.overviewSupportBody;
    return ref.watch(supportPlatformProvider) == SupportPlatform.macos
        ? l10n.overviewSupportBodyStoreMac
        : l10n.overviewSupportBodyStoreWindows;
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
                : _initialBody(l10n),
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
