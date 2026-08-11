/// Review prompt dialog — surfaces a rating/star nudge based on the deploy channel.
///
/// For store builds: opens the Microsoft Store review deep-link via url_launcher.
/// For portable/installer builds: shows links to GitHub star and Store review.
library;

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_urls.dart';
import '../core/l10n/generated/app_localizations.dart';
import '../core/navigation/page_state.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import '../services/deploy_channel_service.dart';
import '../services/review_prompt_service.dart';
import 'animated_prompt_dialog.dart';
import 'wp_button.dart';

/// Override for testing. When non-null, [WpReviewPromptWatcher] uses this value
/// instead of [Platform.isWindows].
///
/// Wp naming — deliberately unprefixed: `@visibleForTesting` seams are not
/// part of the component vocabulary the `Wp` prefix marks, and keeping them
/// plain makes it obvious at the call site that this is a test hook rather
/// than public component API.
@visibleForTesting
bool? platformIsWindowsOverride;

// ---------------------------------------------------------------------------
// Public entry point
// ---------------------------------------------------------------------------

/// Listens to [reviewPromptProvider] and shows the appropriate review dialog
/// when [ReviewPromptState.shouldShowPrompt] becomes `true`.
///
/// Place this widget anywhere in the widget tree — it renders no visible UI
/// of its own and waits (see [WpPostRecordingPromptDelay]) to avoid
/// interrupting the user right at their recording's completion moment.
class WpReviewPromptWatcher extends ConsumerStatefulWidget {
  const WpReviewPromptWatcher({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<WpReviewPromptWatcher> createState() =>
      _WpReviewPromptWatcherState();
}

class _WpReviewPromptWatcherState extends ConsumerState<WpReviewPromptWatcher>
    with WpPostRecordingPromptDelay<WpReviewPromptWatcher> {
  bool get _isWindows => platformIsWindowsOverride ?? Platform.isWindows;

  void _maybeShow(ReviewPromptState state, BuildContext context) {
    maybeShowAfterDelay(
      state.shouldShowPrompt,
      () => _showDialog(context, state.channel),
    );
  }

  Future<void> _showDialog(BuildContext context, DeployChannel channel) async {
    await showWpAnimatedPromptDialog<void>(
      context: context,
      contentBuilder: (ctx, animation) => _ReviewPromptDialog(
        channel: channel,
        isWindows: _isWindows,
        animation: animation,
        onResult: (action) async {
          Navigator.of(ctx).pop();
          markPromptDialogClosed();
          await _handleAction(action);
        },
      ),
    );
    markPromptDialogClosed();
  }

  Future<void> _handleAction(_ReviewAction action) async {
    final notifier = ref.read(reviewPromptProvider.notifier);
    switch (action) {
      case _ReviewAction.rateStore:
        await notifier.markShown();
        await _launchUrl(_storeUrl());
      case _ReviewAction.starGitHub:
        await notifier.markShown();
        await _launchUrl(kGitHubRepoUrl);
      case _ReviewAction.notNow:
        await notifier.dismiss(permanent: false);
      case _ReviewAction.never:
        await notifier.dismiss(permanent: true);
      case _ReviewAction.gateNegative:
        // Negative sentiment → route to the internal feedback page (not the
        // store). Snooze the prompt via the SharedPreferences-backed cooldown
        // so it does not re-ask on the next session.
        await notifier.dismiss(permanent: false);
        ref.read(activePageProvider.notifier).setPage('feedback');
    }
  }

  // Always the Windows Store review URL — the rateStore action is only
  // reachable when the Store button is shown (Windows store/installer/portable).
  String _storeUrl() => kWindowsStoreReviewUrl;

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<ReviewPromptState>(reviewPromptProvider, (_, next) {
      _maybeShow(next, context);
    });
    return widget.child;
  }
}

// ---------------------------------------------------------------------------
// Action enum
// ---------------------------------------------------------------------------

enum _ReviewAction { rateStore, starGitHub, notNow, never, gateNegative }

/// Two-stage flow of the dialog: the neutral sentiment question is shown
/// first ([_GateStage.gate]); a positive answer reveals the review CTAs
/// ([_GateStage.review]). A negative answer never reaches the review stage —
/// it routes the user to the internal feedback page instead.
enum _GateStage { gate, review }

// ---------------------------------------------------------------------------
// Dialog widget
// ---------------------------------------------------------------------------

class _ReviewPromptDialog extends StatefulWidget {
  const _ReviewPromptDialog({
    required this.channel,
    required this.isWindows,
    required this.animation,
    required this.onResult,
  });

  final DeployChannel channel;
  final bool isWindows;
  final Animation<double> animation;
  final void Function(_ReviewAction) onResult;

  @override
  State<_ReviewPromptDialog> createState() => _ReviewPromptDialogState();
}

class _ReviewPromptDialogState extends State<_ReviewPromptDialog> {
  _GateStage _stage = _GateStage.gate;

  @override
  Widget build(BuildContext context) {
    final slide = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: widget.animation, curve: Curves.easeOut));

    final l10n = L10n.of(context);
    final theme = Theme.of(context);

    return Center(
      child: SlideTransition(
        position: slide,
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 380,
            constraints: const BoxConstraints(maxWidth: 380),
            padding: const EdgeInsets.all(WpSpacing.lg),
            decoration: BoxDecoration(
              color: WpColors.surfaceElevated,
              borderRadius: WpRadius.borderLg,
              border: Border.all(color: WpColors.borderSubtle),
              boxShadow: WpShadows.elevated,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.reviewPromptTitle,
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: WpSpacing.sm),
                Text(
                  // The gate stage frames the question as internal feedback
                  // (Microsoft Code of Conduct §3); only the review stage
                  // mentions the store rating.
                  _stage == _GateStage.gate
                      ? l10n.reviewPromptGateBody
                      : l10n.reviewPromptBody,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: WpColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: WpSpacing.lg),
                ..._stageButtons(l10n),
                const SizedBox(height: WpSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: WpButton(
                        label: l10n.reviewPromptNotNow,
                        variant: WpButtonVariant.ghost,
                        onPressed: () => widget.onResult(_ReviewAction.notNow),
                      ),
                    ),
                    Expanded(
                      child: WpButton(
                        label: l10n.reviewPromptNever,
                        variant: WpButtonVariant.ghost,
                        tone: WpButtonTone.neutral,
                        onPressed: () => widget.onResult(_ReviewAction.never),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Resolves the middle button row to the current stage: the neutral gate
  // answers first, then — after a positive answer — the channel-specific
  // review CTAs.
  List<Widget> _stageButtons(L10n l10n) {
    switch (_stage) {
      case _GateStage.gate:
        return _gateButtons(l10n);
      case _GateStage.review:
        return widget.channel == DeployChannel.store
            ? _storeButtons(l10n)
            : _portableButtons(l10n);
    }
  }

  // Neutral sentiment answers — positive reveals the review CTAs, negative
  // routes to the internal feedback page (never to the store).
  List<Widget> _gateButtons(L10n l10n) => [
    WpButton(
      label: l10n.reviewPromptGateYes,
      variant: WpButtonVariant.primary,
      autofocus: true,
      onPressed: () => setState(() => _stage = _GateStage.review),
    ),
    const SizedBox(height: WpSpacing.xs),
    WpButton(
      label: l10n.reviewPromptGateNo,
      variant: WpButtonVariant.secondary,
      onPressed: () => widget.onResult(_ReviewAction.gateNegative),
    ),
  ];

  // Store channel: the primary Store-Review button is accompanied by a
  // secondary GitHub-Stern button (GitHub-Stern-Doppelspur) so store users
  // can also support the open-source project. Mirrors the portable Windows
  // layout (primary store review, secondary GitHub star).
  List<Widget> _storeButtons(L10n l10n) => [
    WpButton(
      label: l10n.reviewPromptYes,
      variant: WpButtonVariant.primary,
      autofocus: true,
      onPressed: () => widget.onResult(_ReviewAction.rateStore),
    ),
    const SizedBox(height: WpSpacing.xs),
    WpButton(
      label: l10n.reviewPromptStarGitHub,
      variant: WpButtonVariant.secondary,
      onPressed: () => widget.onResult(_ReviewAction.starGitHub),
    ),
  ];

  List<Widget> _portableButtons(L10n l10n) {
    if (widget.isWindows) {
      // Windows non-store: both Store review and GitHub star are valid targets.
      return [
        WpButton(
          label: l10n.reviewPromptRateStore,
          variant: WpButtonVariant.primary,
          autofocus: true,
          onPressed: () => widget.onResult(_ReviewAction.rateStore),
        ),
        const SizedBox(height: WpSpacing.xs),
        WpButton(
          label: l10n.reviewPromptStarGitHub,
          variant: WpButtonVariant.secondary,
          onPressed: () => widget.onResult(_ReviewAction.starGitHub),
        ),
      ];
    }
    // macOS / Linux: no store listing exists — show only the GitHub star path.
    return [
      WpButton(
        label: l10n.reviewPromptStarGitHub,
        variant: WpButtonVariant.primary,
        autofocus: true,
        onPressed: () => widget.onResult(_ReviewAction.starGitHub),
      ),
    ];
  }
}
