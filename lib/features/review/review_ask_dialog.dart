/// The rating dialog (#2185, maintainer decision 2026-11-24).
///
/// Replaces the quiet rate/share card of the Übersicht: the card alone did
/// not reach people. When the review prompt service finds the ask due, the
/// dialog waits for a good moment: a run of good dictations today
/// ([kReviewStreakMin]), the nudge gate (no dictation, 30 s without input in
/// the window), the WhisPaste window in front, no problem in the status line,
/// no onboarding, and the session's one prompt slot
/// ([PromptDisplayArbiter]). Everyone gets the same ask; nobody is asked
/// first whether they like the app (no review gating).
///
/// The rating way follows the build ([ReviewRateWay]): Mac App Store asks
/// through Apple's own dialog, the Microsoft Store package through the
/// Store's own rate-and-review dialog, every other build for a GitHub star.
/// Next to it the share buttons recommend WhisPaste with one click.
library;

import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_urls.dart';
import '../../core/config/build_config.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/l10n/locale_provider.dart';
import '../../core/logging/app_logger.dart';
import '../../core/onboarding/onboarding_surface.dart';
import '../../core/review/review_ask.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../services/deploy_channel_service.dart';
import '../../services/nudge_gate.dart';
import '../../services/prompt_display_arbiter.dart';
import '../../services/review_prompt_service.dart';
import '../../services/review_streak_provider.dart';
import '../../widgets/dialog.dart';
import '../../widgets/wp_notice_bar.dart';
import '../help/recommend_share_buttons.dart';
import '../overview/overview_header.dart' show overviewStatusIssueProvider;
import '../overview/overview_providers.dart' show overviewPrefsProvider;
import '../settings/sections/review_support_section.dart'
    show openRateDestination;

final _log = AppLogger('ReviewAsk');

/// The rating way of this build. Overridable in tests.
final reviewRateWayProvider = Provider<ReviewRateWay>(
  (ref) => reviewRateWayFor(
    channel: ref.watch(deployChannelProvider),
    isMasBuild: kIsMasBuild,
    isWindows: defaultTargetPlatform == TargetPlatform.windows,
  ),
);

/// The page a recommendation points to: the store listing in a store build
/// (the friend installs from there), the website everywhere else.
String reviewShareBaseUrl(ReviewRateWay way, String languageCode) =>
    switch (way) {
      ReviewRateWay.appleSystemDialog => kMacAppStoreListingUrl,
      ReviewRateWay.microsoftStoreDialog => kMicrosoftStoreListingUrl,
      ReviewRateWay.githubStar => websiteLocalizedHomeUrl(languageCode),
    };

/// How the dialog was left.
enum ReviewAskAnswer {
  /// The rating button (store dialog or GitHub star).
  rate,

  /// "Später": a pause of 90 days, unless the user already shared.
  later,

  /// "Nicht mehr fragen": never again (the card's old key).
  never,

  /// "Schließen" in the Mac App Store build, where Apple's dialog already
  /// counted as the ask.
  done,

  /// A hotkey closed it: no answer, no pause.
  cancelled,
}

/// Mounted once in the app shell; renders nothing. Opens the rating dialog
/// at the next good moment while the ask is due.
class ReviewAskWatcher extends ConsumerStatefulWidget {
  const ReviewAskWatcher({super.key});

  @override
  ConsumerState<ReviewAskWatcher> createState() => _ReviewAskWatcherState();
}

class _ReviewAskWatcherState extends ConsumerState<ReviewAskWatcher> {
  bool _running = false;
  bool _askedThisSession = false;
  late final AppLifecycleListener _lifecycle;
  Completer<void>? _resumed;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _onResume);
    ref.listenManual(reviewStreakProvider, (_, _) => _maybeStart());
    ref.listenManual(
      reviewPromptProvider.select((s) => s.shouldShowPrompt),
      (_, _) => _maybeStart(),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _onResume() {
    // Coming to the front is activity: the 30 s of calm start now, so the
    // dialog never greets the user the moment they switch to WhisPaste.
    ref.read(nudgeGateProvider).noteInput();
    final waiting = _resumed;
    _resumed = null;
    if (waiting != null && !waiting.isCompleted) waiting.complete();
  }

  static bool _windowActive() {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  void _maybeStart() {
    if (_running || _askedThisSession || !mounted) return;
    if (!ref.read(reviewStreakProvider.notifier).met) return;
    _running = true;
    unawaited(_run().whenComplete(() => _running = false));
  }

  /// Everything but the window and the stored store rating.
  bool _momentHolds() =>
      ref.read(reviewPromptProvider).shouldShowPrompt &&
      ref.read(reviewStreakProvider.notifier).met &&
      ref.read(overviewStatusIssueProvider) == null &&
      !ref.read(onboardingSurfaceActiveProvider);

  Future<void> _run() async {
    try {
      final prompt = ref.read(reviewPromptProvider.notifier);
      // Platforms without a paste receipt never ask from the pipeline.
      if (!ref.read(reviewPromptProvider).shouldShowPrompt) {
        await prompt.checkAndMaybePrompt();
      }
      while (mounted && _momentHolds()) {
        await ref.read(nudgeGateProvider).whenAllowed();
        if (!mounted) return;
        if (_windowActive()) break;
        final resumed = _resumed ??= Completer<void>();
        await resumed.future;
      }
      if (!mounted) return;
      final storeRated = await reviewStoreRated();
      if (!mounted) return;
      final mayOpen = reviewAskMayOpen(
        due: ref.read(reviewPromptProvider).shouldShowPrompt,
        storeRated: storeRated,
        streakMet: ref.read(reviewStreakProvider.notifier).met,
        problemShown: ref.read(overviewStatusIssueProvider) != null,
        onboardingActive: ref.read(onboardingSurfaceActiveProvider),
        windowActive: _windowActive(),
      );
      if (!mayOpen) return;
      await _ask();
    } on Object catch (e) {
      _log.warning('rating dialog failed: ${e.runtimeType}');
    }
  }

  Future<void> _ask() async {
    final arbiter = ref.read(promptDisplayArbiterProvider);
    final close = ReviewAskCloser();
    if (!arbiter.tryClaim(PromptOwner.review, close: close.close)) return;
    _askedThisSession = true;
    final prompt = ref.read(reviewPromptProvider.notifier);
    final way = ref.read(reviewRateWayProvider);
    final channel = ref.read(deployChannelProvider);
    var shared = false;
    try {
      prompt.trackAsk(ReviewAction.shown);
      if (way == ReviewRateWay.appleSystemDialog) {
        // Apple's dialog is the rating ask in this build; it counts as asked
        // whether or not StoreKit shows it (it may suppress it silently).
        unawaited(_requestSystemReview());
      }
      final answer = await showReviewAskDialog(
        context: context,
        way: way,
        closer: close,
        onShared: (id) {
          prompt.trackShare(id);
          if (!shared) {
            shared = true;
            unawaited(prompt.markShown(answer: null));
          }
        },
      );
      if (answer != ReviewAskAnswer.cancelled) _noteAnswered();
      switch (answer ?? ReviewAskAnswer.later) {
        case ReviewAskAnswer.rate:
          await _rate(way, channel);
        case ReviewAskAnswer.later:
          // A share already counted as an answer, and in the Mac App Store
          // build Apple's dialog did; otherwise "Später" (or Escape) pauses.
          if (!shared && way != ReviewRateWay.appleSystemDialog) {
            await prompt.dismiss(permanent: false);
          }
        case ReviewAskAnswer.never:
          await prompt.dismiss(permanent: true);
        case ReviewAskAnswer.done:
        case ReviewAskAnswer.cancelled:
          break;
      }
    } finally {
      arbiter.release(PromptOwner.review);
    }
  }

  Future<void> _requestSystemReview() async {
    final prompt = ref.read(reviewPromptProvider.notifier);
    try {
      await ref.read(systemReviewRequesterProvider)();
    } on Exception catch (e) {
      // No dialog available: still counted, so the ask does not loop.
      _log.warning('system review request failed: $e');
    }
    await prompt.markShown(answer: null);
  }

  Future<void> _rate(ReviewRateWay way, DeployChannel channel) async {
    final prompt = ref.read(reviewPromptProvider.notifier);
    await prompt.markShown();
    switch (way) {
      case ReviewRateWay.microsoftStoreDialog:
        final outcome = await ref.read(storeRateRequesterProvider)();
        if (outcome == StoreRateOutcome.succeeded) {
          await prompt.markStoreRated();
          if (mounted) {
            showWpConfirmation(
              context,
              id: 'review-ask-thanks',
              message: L10n.of(context).reviewAskThanks,
            );
          }
        } else if (storeRateNeedsFallback(outcome)) {
          _log.info('store rating dialog unavailable (${outcome.name})');
          await openRateDestination(channel);
        }
      case ReviewRateWay.githubStar:
        await openRateDestination(channel);
      case ReviewRateWay.appleSystemDialog:
        // No rating button in this build.
        break;
    }
  }

  /// An answered ask keeps the Übersicht's hint place quiet for the day, so
  /// the support card never follows on the same day.
  void _noteAnswered() => unawaited(
    ref.read(overviewPrefsProvider.notifier).noteAskCardDay(clock.now()),
  );

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Lets the arbiter close the open dialog (hotkey) without an answer.
final class ReviewAskCloser {
  BuildContext? dialogContext;

  void close() {
    final context = dialogContext;
    if (context == null || !context.mounted) return;
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive) return;
    Navigator.of(context).removeRoute(route, ReviewAskAnswer.cancelled);
  }
}

/// Shows the rating dialog for [way]. [onShared] gets the channel id of
/// every share; the dialog stays open after a share.
Future<ReviewAskAnswer?> showReviewAskDialog({
  required BuildContext context,
  required ReviewRateWay way,
  required ValueChanged<String> onShared,
  ReviewAskCloser? closer,
}) {
  final l10n = L10n.of(context);
  final mac = way == ReviewRateWay.appleSystemDialog;
  return showWpDialog<ReviewAskAnswer>(
    context: context,
    title: l10n.reviewAskTitle,
    // Wide: eleven share buttons fit in two or three rows instead of six,
    // so the ask stays one glance without scrolling.
    size: WpDialogSize.wide,
    answersInRow: !mac,
    content: _ReviewAskBody(way: way, onShared: onShared, closer: closer),
    actions: [
      if (mac)
        WpDialogAction<ReviewAskAnswer>(
          label: l10n.actionClose,
          testId: 'review-ask-close',
          role: WpDialogActionRole.primary,
          value: ReviewAskAnswer.done,
        )
      else ...[
        WpDialogAction<ReviewAskAnswer>(
          label: way == ReviewRateWay.microsoftStoreDialog
              ? l10n.reviewAskRateStore
              : l10n.reviewAskRateGitHub,
          testId: 'review-ask-rate',
          role: WpDialogActionRole.primary,
          value: ReviewAskAnswer.rate,
        ),
        WpDialogAction<ReviewAskAnswer>(
          label: l10n.overviewAskLater,
          testId: 'review-ask-later',
          role: WpDialogActionRole.alternative,
          value: ReviewAskAnswer.later,
        ),
      ],
      WpDialogAction<ReviewAskAnswer>(
        label: l10n.overviewAskNever,
        testId: 'review-ask-never',
        role: WpDialogActionRole.cancel,
        value: ReviewAskAnswer.never,
      ),
    ],
  );
}

class _ReviewAskBody extends ConsumerWidget {
  const _ReviewAskBody({
    required this.way,
    required this.onShared,
    required this.closer,
  });

  final ReviewRateWay way;
  final ValueChanged<String> onShared;
  final ReviewAskCloser? closer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    closer?.dialogContext = context;
    final l10n = L10n.of(context);
    final language = ref.watch(localeProvider).languageCode;
    final body = switch (way) {
      ReviewRateWay.appleSystemDialog => l10n.reviewAskBodyMac,
      ReviewRateWay.microsoftStoreDialog => l10n.reviewAskBodyStore,
      ReviewRateWay.githubStar => l10n.reviewAskBodyGitHub,
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(identifier: 'review-ask-body', child: Text(body)),
        const SizedBox(height: WpSpacing.md),
        Text(l10n.reviewAskShareHeading, style: WpTextStyles.rowNote),
        const SizedBox(height: WpSpacing.xs),
        RecommendShareButtons(
          baseUrl: reviewShareBaseUrl(way, language),
          languageCode: language,
          testIdPrefix: 'review-ask-share',
          onShared: onShared,
        ),
      ],
    );
  }
}
