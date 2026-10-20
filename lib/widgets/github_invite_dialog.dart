/// GitHub star invitation for Store builds — see `services/github_invite_service.dart`.
///
/// Shown only on the Store channel. The copy never refers to a store rating.
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_urls.dart';
import '../core/l10n/generated/app_localizations.dart';
import '../core/recording/recording_state.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import '../services/nudge_gate.dart';
import '../services/prompt_display_arbiter.dart';
import '../services/telemetry_service.dart';
import '../services/github_invite_service.dart';
import 'animated_prompt_dialog.dart';
import 'wp_button.dart';

/// Override for testing. When non-null, the watcher uses this instead of
/// [Platform.isMacOS] to pick the telemetry store label (`mas` or `msstore`).
@visibleForTesting
bool? githubInviteIsMacOsOverride;

/// Listens to [githubInviteProvider] and shows the invitation after the
/// post-recording delay. Renders no UI of its own.
class WpGitHubInviteWatcher extends ConsumerStatefulWidget {
  const WpGitHubInviteWatcher({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<WpGitHubInviteWatcher> createState() =>
      _WpGitHubInviteWatcherState();
}

enum _InviteChoice { openGitHub, later, never }

class _WpGitHubInviteWatcherState extends ConsumerState<WpGitHubInviteWatcher>
    with WpPostRecordingPromptDelay<WpGitHubInviteWatcher> {
  bool get _isMacOs => githubInviteIsMacOsOverride ?? Platform.isMacOS;

  String get _storeName => _isMacOs ? 'mas' : 'msstore';

  @override
  Future<void> waitForNudgeGate() => ref.read(nudgeGateProvider).whenAllowed();

  void _maybeShow(GitHubInviteState state, BuildContext context) {
    maybeShowAfterDelay(state.shouldShowInvite, () {
      unawaited(_show(context));
    });
  }

  /// Opt-out telemetry for the invitation (closed labels only, no content).
  void _track(String action, String name) => ref
      .read(telemetryProvider)
      .trackEvent(category: 'review', action: action, name: name);

  Future<void> _show(BuildContext context) async {
    final arbiter = ref.read(promptDisplayArbiterProvider);
    final notifier = ref.read(githubInviteProvider.notifier);

    // Never during a recording or transcription; re-evaluated after the next one.
    if (ref.read(recordingPhaseProvider) != RecordingPhase.idle) {
      notifier.deferInvite();
      markPromptDialogClosed();
      return;
    }

    var closedByHotkey = false;
    final claimed = arbiter.tryClaim(
      PromptOwner.githubInvite,
      close: () {
        closedByHotkey = true;
        unawaited(Navigator.of(context, rootNavigator: true).maybePop());
      },
    );
    if (!claimed) {
      notifier.deferInvite();
      markPromptDialogClosed();
      return;
    }

    _InviteChoice? chosen;
    try {
      final dialog = showWpAnimatedPromptDialog<void>(
        context: context,
        contentBuilder: (ctx, animation) => _GitHubInviteContent(
          animation: animation,
          onResult: (choice) {
            chosen = choice;
            Navigator.of(ctx).pop();
          },
        ),
      );
      // Counted as displayed the moment the dialog opens.
      unawaited(notifier.recordImpression());
      _track('github_invite_shown', _storeName);
      await dialog;

      final choice = chosen;
      if (choice == _InviteChoice.openGitHub) {
        _track('github_invite_clicked', _storeName);
        await notifier.markStarOpened();
        await _launchGitHub();
      } else if (choice == _InviteChoice.later) {
        _track('github_invite_declined', 'later');
        await notifier.dismiss(permanent: false);
      } else if (choice == _InviteChoice.never) {
        _track('github_invite_declined', 'never');
        await notifier.dismiss(permanent: true);
      } else if (closedByHotkey) {
        notifier.deferInvite();
      } else {
        // Escape or a click outside counts as "Später".
        _track('github_invite_declined', 'dismissed');
        await notifier.dismiss(permanent: false);
      }
    } finally {
      arbiter.release(PromptOwner.githubInvite);
      markPromptDialogClosed();
    }
  }

  Future<void> _launchGitHub() async {
    final uri = Uri.parse(kGitHubRepoUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<GitHubInviteState>(githubInviteProvider, (_, next) {
      _maybeShow(next, context);
    });
    return widget.child;
  }
}

class _GitHubInviteContent extends StatelessWidget {
  const _GitHubInviteContent({required this.animation, required this.onResult});

  final Animation<double> animation;
  final void Function(_InviteChoice) onResult;

  @override
  Widget build(BuildContext context) {
    final slide = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut));
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
                  l10n.githubInviteTitle,
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                  key: const ValueKey('github-invite-title'),
                ),
                const SizedBox(height: WpSpacing.sm),
                Text(
                  l10n.githubInviteBody,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: WpColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: WpSpacing.lg),
                WpButton(
                  key: const ValueKey('github-invite-open'),
                  label: l10n.githubInviteOpen,
                  variant: WpButtonVariant.primary,
                  autofocus: true,
                  onPressed: () => onResult(_InviteChoice.openGitHub),
                ),
                const SizedBox(height: WpSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: WpButton(
                        key: const ValueKey('github-invite-later'),
                        label: l10n.githubInviteLater,
                        variant: WpButtonVariant.ghost,
                        onPressed: () => onResult(_InviteChoice.later),
                      ),
                    ),
                    Expanded(
                      child: WpButton(
                        key: const ValueKey('github-invite-never'),
                        label: l10n.githubInviteNever,
                        variant: WpButtonVariant.ghost,
                        tone: WpButtonTone.neutral,
                        onPressed: () => onResult(_InviteChoice.never),
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
}
