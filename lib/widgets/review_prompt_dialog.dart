/// Review prompt dialog — surfaces a rating/star nudge based on the deploy channel.
///
/// Store builds (Mac App Store, Microsoft Store) do not get this dialog: they
/// make the OS rating request instead. Portable and installer builds get the
/// dialog with links to the GitHub star and, on Windows, the Store review page.
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_urls.dart';
import '../core/l10n/generated/app_localizations.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import '../services/deploy_channel_service.dart';
import '../services/nudge_gate.dart';
import '../services/prompt_display_arbiter.dart';
import '../services/review_prompt_service.dart';
import '../services/store_review_request_service.dart';
import '../services/telemetry_service.dart';
import 'animated_prompt_dialog.dart';
import 'wp_button.dart';
import 'wp_toast_dock.dart';
import 'external_link.dart';

/// Override for testing. When non-null, [WpReviewPromptWatcher] uses this value
/// instead of [Platform.isWindows].
///
/// Wp naming — deliberately unprefixed: `@visibleForTesting` seams are not
/// part of the component vocabulary the `Wp` prefix marks, and keeping them
/// plain makes it obvious at the call site that this is a test hook rather
/// than public component API.
@visibleForTesting
bool? platformIsWindowsOverride;

/// Override for testing. When non-null, [WpReviewPromptWatcher] uses this value
/// instead of [Platform.isMacOS] to decide whether to make the native request.
@visibleForTesting
bool? platformIsMacOsOverride;

/// Whether the review prompt asks through the OS rating request instead of
/// showing its own dialog: the store channel on macOS or Windows only. Linux
/// has no store listing and never requests a store rating (growth review
/// GR-011); its GitHub star dialog is unaffected.
@visibleForTesting
bool usesNativeStoreRequest({
  required DeployChannel channel,
  required bool isMacOs,
  required bool isWindows,
}) => channel == DeployChannel.store && (isMacOs || isWindows);

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
  @override
  Future<void> waitForNudgeGate() => ref.read(nudgeGateProvider).whenAllowed();

  bool get _isWindows => platformIsWindowsOverride ?? Platform.isWindows;
  bool get _isMacOs => platformIsMacOsOverride ?? Platform.isMacOS;

  /// Store builds (Mac App Store, Microsoft Store) ask through the OS rating
  /// request instead of showing our own dialog: a custom prompt is not allowed
  /// there, and the system request is the sanctioned way to ask for a rating.
  /// Unpackaged Windows builds keep the dialog and its Settings link.
  bool _usesNativeRequest(DeployChannel channel) => usesNativeStoreRequest(
    channel: channel,
    isMacOs: _isMacOs,
    isWindows: _isWindows,
  );

  void _maybeShow(ReviewPromptState state, BuildContext context) {
    maybeShowAfterDelay(state.shouldShowPrompt, () {
      if (_usesNativeRequest(state.channel)) {
        unawaited(_requestNative());
      } else {
        unawaited(_showDialog(context, state.channel));
      }
    });
  }

  /// Opt-out telemetry for the review funnel (growth review R-10). Only closed
  /// labels are sent: no transcript, no text, no identifiers.
  void _track(String action, String name) => ref
      .read(telemetryProvider)
      .trackEvent(category: 'review', action: action, name: name);

  Future<void> _requestNative() async {
    final arbiter = ref.read(promptDisplayArbiterProvider);
    final notifier = ref.read(reviewPromptProvider.notifier);
    final claimed = arbiter.tryClaim(PromptOwner.review, close: () {});
    if (!claimed) {
      notifier.deferPrompt();
      markPromptDialogClosed();
      return;
    }
    final store = _isMacOs ? 'mas' : 'msstore';
    try {
      // At most 3 store requests per 365 days (growth review GR-009). A capped
      // request is not made at all and does not show a dialog either.
      if (!await notifier.nativeRequestAllowed()) {
        notifier.deferPrompt();
        return;
      }
      // "native_requested" counts requests made to the OS. The OS does not
      // report whether it displayed a sheet, so this is not a display count.
      _track('native_requested', store);
      final outcome = await ref.read(nativeStoreReviewRequestProvider)();
      switch (outcome) {
        case NativeReviewOutcome.requested:
          await notifier.markNativeRequested();
        case NativeReviewOutcome.unavailable:
          _track('native_unavailable', store);
          notifier.deferPrompt();
        case NativeReviewOutcome.failed:
          _track('native_failed', store);
          notifier.deferPrompt();
      }
    } finally {
      arbiter.release(PromptOwner.review);
      markPromptDialogClosed();
    }
  }

  Future<void> _showDialog(BuildContext context, DeployChannel channel) async {
    final arbiter = ref.read(promptDisplayArbiterProvider);
    final notifier = ref.read(reviewPromptProvider.notifier);
    var closedByHotkey = false;
    final claimed = arbiter.tryClaim(
      PromptOwner.review,
      close: () {
        closedByHotkey = true;
        unawaited(Navigator.of(context, rootNavigator: true).maybePop());
      },
    );
    if (!claimed) {
      notifier.deferPrompt();
      markPromptDialogClosed();
      return;
    }
    _ReviewAction? chosen;
    try {
      _track('dialog_opened', channel.name);
      await showWpAnimatedPromptDialog<void>(
        context: context,
        contentBuilder: (ctx, animation) => _ReviewPromptDialog(
          isWindows: _isWindows,
          animation: animation,
          onResult: (action) {
            chosen = action;
            Navigator.of(ctx).pop();
          },
        ),
      );
      // Escape and a click outside share the "not now" snooze, like the
      // support prompt. A hotkey close records nothing.
      final action = chosen;
      if (action != null) {
        _track('choice', action.name);
        await _handleAction(action);
      } else if (closedByHotkey) {
        _track('closed', 'hotkey');
        notifier.deferPrompt();
      } else {
        _track('closed', 'dismissed');
        await notifier.dismiss(permanent: false);
      }
    } finally {
      arbiter.release(PromptOwner.review);
      markPromptDialogClosed();
    }
  }

  Future<void> _handleAction(_ReviewAction action) async {
    final notifier = ref.read(reviewPromptProvider.notifier);
    switch (action) {
      case _ReviewAction.rateStore:
        await notifier.markShown();
        if (!mounted) return;
        await openExternalUrl(context, kWindowsStoreReviewUrl);
      case _ReviewAction.starGitHub:
        await notifier.markShown();
        if (!mounted) return;
        await openExternalUrl(context, kGitHubRepoUrl);
      case _ReviewAction.notNow:
        await notifier.dismiss(permanent: false);
      case _ReviewAction.never:
        await notifier.dismiss(permanent: true);
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

enum _ReviewAction { rateStore, starGitHub, notNow, never }

// ---------------------------------------------------------------------------
// Dialog widget
// ---------------------------------------------------------------------------

class _ReviewPromptDialog extends StatefulWidget {
  const _ReviewPromptDialog({
    required this.isWindows,
    required this.animation,
    required this.onResult,
  });

  final bool isWindows;
  final Animation<double> animation;
  final void Function(_ReviewAction) onResult;

  @override
  State<_ReviewPromptDialog> createState() => _ReviewPromptDialogState();
}

class _ReviewPromptDialogState extends State<_ReviewPromptDialog> {
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
                  l10n.reviewPromptBody,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: WpColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: WpSpacing.lg),
                ..._portableButtons(l10n),
                const SizedBox(height: WpSpacing.sm),
                WpToastDockReserve(
                  child: Row(
                    children: [
                      Expanded(
                        child: WpButton(
                          label: l10n.reviewPromptNotNow,
                          variant: WpButtonVariant.ghost,
                          // Enter on the default focus must not open the store (UIA-FBK-01).
                          autofocus: true,
                          onPressed: () =>
                              widget.onResult(_ReviewAction.notNow),
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
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _portableButtons(L10n l10n) {
    if (widget.isWindows) {
      // Windows non-store: both Store review and GitHub star are valid targets.
      return [
        WpButton(
          label: l10n.reviewPromptRateStore,
          variant: WpButtonVariant.primary,
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
        onPressed: () => widget.onResult(_ReviewAction.starGitHub),
      ),
    ];
  }
}
