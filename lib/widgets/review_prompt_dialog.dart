/// Review prompt dialog — surfaces a rating/star nudge based on the deploy channel.
///
/// For store builds: opens the Microsoft Store review deep-link via url_launcher.
/// For portable/installer builds: shows links to GitHub star and Store review.
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_urls.dart';
import '../core/l10n/generated/app_localizations.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import '../services/deploy_channel_service.dart';
import '../services/review_prompt_service.dart';

/// Override for testing. When non-null, [ReviewPromptWatcher] uses this value
/// instead of [Platform.isWindows].
@visibleForTesting
bool? platformIsWindowsOverride;

// ---------------------------------------------------------------------------
// Public entry point
// ---------------------------------------------------------------------------

/// Listens to [reviewPromptProvider] and shows the appropriate review dialog
/// when [ReviewPromptState.shouldShowPrompt] becomes `true`.
///
/// Place this widget anywhere in the widget tree — it renders no visible UI
/// of its own and uses a 1-second delay to avoid interrupting the user mid-task.
class ReviewPromptWatcher extends ConsumerStatefulWidget {
  const ReviewPromptWatcher({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ReviewPromptWatcher> createState() =>
      _ReviewPromptWatcherState();
}

class _ReviewPromptWatcherState extends ConsumerState<ReviewPromptWatcher> {
  Timer? _delay;
  bool _dialogShowing = false;

  bool get _isWindows => platformIsWindowsOverride ?? Platform.isWindows;

  @override
  void dispose() {
    _delay?.cancel();
    super.dispose();
  }

  void _maybeShow(ReviewPromptState state, BuildContext context) {
    if (!state.shouldShowPrompt || _dialogShowing) return;
    _dialogShowing = true;
    _delay = Timer(const Duration(seconds: 1), () {
      if (!mounted) {
        _dialogShowing = false;
        return;
      }
      _showDialog(context, state.channel);
    });
  }

  Future<void> _showDialog(BuildContext context, DeployChannel channel) async {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.transparent,
      transitionDuration: WpMotion.smooth,
      pageBuilder: (_, p1, p2) => const SizedBox.shrink(),
      transitionBuilder: (ctx, animation, p1, p2) {
        final opacity = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOut,
        );
        final isDark = Theme.of(ctx).brightness == Brightness.dark;

        return FadeTransition(
          opacity: opacity,
          child: Stack(
            children: [
              Positioned.fill(
                child: ColoredBox(
                  color:
                      (isDark
                              ? const Color(0xFF000000)
                              : const Color(0xFFFFFFFF))
                          .withValues(alpha: isDark ? 0.45 : 0.35),
                ),
              ),
              _ReviewPromptDialog(
                channel: channel,
                isWindows: _isWindows,
                animation: animation,
                onResult: (action) async {
                  Navigator.of(ctx).pop();
                  _dialogShowing = false;
                  await _handleAction(action);
                },
              ),
            ],
          ),
        );
      },
    );
    _dialogShowing = false;
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

enum _ReviewAction { rateStore, starGitHub, notNow, never }

// ---------------------------------------------------------------------------
// Dialog widget
// ---------------------------------------------------------------------------

class _ReviewPromptDialog extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final slide = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut));

    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isStore = channel == DeployChannel.store;

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
              color: isDark
                  ? WpColorsDark.surfaceElevated
                  : WpColorsLight.surfaceElevated,
              borderRadius: WpRadius.borderLg,
              border: Border.all(
                color: isDark
                    ? WpColorsDark.borderSubtle
                    : WpColorsLight.borderSubtle,
              ),
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
                    color: isDark
                        ? WpColorsDark.textSecondary
                        : WpColorsLight.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: WpSpacing.lg),
                if (isStore)
                  ..._storeButtons(l10n, theme)
                else
                  ..._portableButtons(l10n, theme, isDark),
                const SizedBox(height: WpSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => onResult(_ReviewAction.notNow),
                        child: Text(l10n.reviewPromptNotNow),
                      ),
                    ),
                    Expanded(
                      child: TextButton(
                        onPressed: () => onResult(_ReviewAction.never),
                        child: Text(
                          l10n.reviewPromptNever,
                          style: TextStyle(
                            color: isDark
                                ? WpColorsDark.textSecondary
                                : WpColorsLight.textSecondary,
                            fontSize: 12,
                          ),
                        ),
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

  List<Widget> _storeButtons(L10n l10n, ThemeData theme) => [
    FilledButton(
      autofocus: true,
      onPressed: () => onResult(_ReviewAction.rateStore),
      child: Text(l10n.reviewPromptYes),
    ),
  ];

  List<Widget> _portableButtons(L10n l10n, ThemeData theme, bool isDark) {
    if (isWindows) {
      // Windows non-store: both Store review and GitHub star are valid targets.
      return [
        FilledButton(
          autofocus: true,
          onPressed: () => onResult(_ReviewAction.rateStore),
          child: Text(l10n.reviewPromptRateStore),
        ),
        const SizedBox(height: WpSpacing.xs),
        OutlinedButton(
          onPressed: () => onResult(_ReviewAction.starGitHub),
          child: Text(l10n.reviewPromptStarGitHub),
        ),
      ];
    }
    // macOS / Linux: no store listing exists — show only the GitHub star path.
    return [
      FilledButton(
        autofocus: true,
        onPressed: () => onResult(_ReviewAction.starGitHub),
        child: Text(l10n.reviewPromptStarGitHub),
      ),
    ];
  }
}
