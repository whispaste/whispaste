import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/app_urls.dart' show websiteHomeUrl;
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/overview/overview_logic.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../services/deploy_channel_service.dart';
import '../../services/review_prompt_service.dart';
import '../../widgets/toast.dart';
import '../../widgets/wp_button.dart';
import '../../widgets/wp_card.dart';
import '../../widgets/wp_icon_button.dart';
import '../settings/sections/review_support_section.dart'
    show openRateDestination;
import 'overview_header.dart' show overviewStatusIssueProvider;
import 'overview_providers.dart';

/// The milestone or rate/share card of this visit, or null. It follows a
/// good moment only: [overviewAskCard] holds the rules, the review prompt
/// service decides when a rating ask is due.
final overviewAskCardProvider = Provider.autoDispose<OverviewAskCard?>((ref) {
  final prefs = ref.watch(overviewPrefsProvider);
  if (!prefs.loaded) return null;
  final total = ref.watch(overviewDictationTotalProvider).value;
  if (total == null) return null;
  final day = prefs.askCardDay;
  return overviewAskCard(
    dictations: total,
    milestonesSeen: prefs.milestonesSeen,
    rateDue: ref.watch(reviewPromptProvider).shouldShowPrompt,
    problemShown: ref.watch(overviewStatusIssueProvider) != null,
    anyCardShownOn: day == null ? null : DateTime.tryParse(day),
    now: clock.now(),
  );
});

/// The quiet card in the hint place after a milestone or, later, the ask to
/// rate or share WhisPaste. No reward, no pressure: "Später" waits, the
/// close button stops asking.
class OverviewAskCardView extends ConsumerWidget {
  const OverviewAskCardView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (ref.watch(overviewAskCardProvider)) {
      final OverviewMilestoneCard m => _Milestone(count: m.count),
      OverviewRateShareCard() => const _RateShare(),
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
        tooltip: l10n.overviewRateNever,
        onPressed: () => notifier.dismiss(permanent: true),
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
                  await notifier.markShown();
                  await openRateDestination(channel);
                },
              ),
              WpButton(
                testId: 'overview-share',
                label: l10n.overviewShareCopyLink,
                variant: WpButtonVariant.secondary,
                size: WpButtonSize.dense,
                onPressed: () => _copyLink(context, notifier),
              ),
              WpButton(
                testId: 'overview-rate-later',
                label: l10n.overviewRateLater,
                variant: WpButtonVariant.ghost,
                size: WpButtonSize.dense,
                onPressed: () => notifier.dismiss(permanent: false),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Copies the website link only: no text, no recording, nothing personal.
  void _copyLink(BuildContext context, ReviewPromptNotifier notifier) {
    final l10n = L10n.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    unawaited(Clipboard.setData(ClipboardData(text: websiteHomeUrl(lang))));
    WpToast.show(
      context,
      message: l10n.overviewShareCopied,
      type: WpToastType.info,
    );
    unawaited(notifier.markShown());
  }
}
