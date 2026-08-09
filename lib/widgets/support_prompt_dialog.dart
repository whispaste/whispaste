/// Support prompt dialog — surfaces a support/sponsor nudge mirroring the
/// structure of `review_prompt_dialog.dart`, but fully independent of it
/// (own provider, own watcher, own dismissal semantics).
///
/// Reuses the About page's existing support copy (`aboutSupportTitle` /
/// `aboutSupportDescription` / `aboutGitHubSponsors` / `aboutKofi`) for the
/// initial ask, and its own distinct copy for the one-time recurring
/// follow-up (`supportPromptRecurringTitle` / `supportPromptRecurringDescription`).
/// Reuses `reviewPromptNever` for the dismiss action — dismissing here starts
/// a snooze rather than a permanent block; see `support_prompt_service.dart`.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_urls.dart';
import '../core/l10n/generated/app_localizations.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import '../services/prompt_timing.dart';
import '../services/support_prompt_service.dart';
import 'wp_button.dart';

// ---------------------------------------------------------------------------
// Public entry point
// ---------------------------------------------------------------------------

/// Listens to [supportPromptProvider] and shows the support dialog when
/// [SupportPromptState.shouldShowPrompt] becomes `true`.
///
/// Place this widget anywhere in the widget tree — it renders no visible UI
/// of its own and waits [kPostRecordingPromptDelay] before showing, so it
/// never interrupts a recording's completion moment.
class WpSupportPromptWatcher extends ConsumerStatefulWidget {
  const WpSupportPromptWatcher({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<WpSupportPromptWatcher> createState() =>
      _WpSupportPromptWatcherState();
}

class _WpSupportPromptWatcherState
    extends ConsumerState<WpSupportPromptWatcher> {
  Timer? _delay;
  bool _dialogShowing = false;

  @override
  void dispose() {
    _delay?.cancel();
    super.dispose();
  }

  void _maybeShow(SupportPromptState state, BuildContext context) {
    if (!state.shouldShowPrompt || _dialogShowing) return;
    _dialogShowing = true;
    _delay = Timer(kPostRecordingPromptDelay, () {
      if (!mounted) {
        _dialogShowing = false;
        return;
      }
      _showDialog(context, state.kind);
    });
  }

  Future<void> _showDialog(BuildContext context, SupportPromptKind kind) async {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.transparent,
      transitionDuration: WpMotion.durationFor(context, WpMotion.smooth),
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
                child: ColoredBox(color: wpDialogBarrierColor(isDark)),
              ),
              _SupportPromptDialog(
                animation: animation,
                kind: kind,
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

  Future<void> _handleAction(_SupportAction action) async {
    final notifier = ref.read(supportPromptProvider.notifier);
    switch (action) {
      case _SupportAction.gitHubSponsors:
        await notifier.markLinkOpened();
        await _launchUrl(kGitHubSponsorsUrl);
      case _SupportAction.kofi:
        await notifier.markLinkOpened();
        await _launchUrl(kKofiUrl);
      case _SupportAction.dismiss:
        await notifier.dismiss();
    }
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<SupportPromptState>(supportPromptProvider, (_, next) {
      _maybeShow(next, context);
    });
    return widget.child;
  }
}

// ---------------------------------------------------------------------------
// Action enum
// ---------------------------------------------------------------------------

enum _SupportAction { gitHubSponsors, kofi, dismiss }

// ---------------------------------------------------------------------------
// Dialog widget
// ---------------------------------------------------------------------------

class _SupportPromptDialog extends StatelessWidget {
  const _SupportPromptDialog({
    required this.animation,
    required this.kind,
    required this.onResult,
  });

  final Animation<double> animation;
  final SupportPromptKind kind;
  final void Function(_SupportAction) onResult;

  @override
  Widget build(BuildContext context) {
    final slide = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut));

    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isRecurringFollowUp = kind == SupportPromptKind.recurringFollowUp;
    final title = isRecurringFollowUp
        ? l10n.supportPromptRecurringTitle
        : l10n.aboutSupportTitle;
    final description = isRecurringFollowUp
        ? l10n.supportPromptRecurringDescription
        : l10n.aboutSupportDescription;

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
                  title,
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: WpSpacing.sm),
                Text(
                  description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: isDark
                        ? WpColorsDark.textSecondary
                        : WpColorsLight.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: WpSpacing.lg),
                WpButton(
                  label: l10n.aboutGitHubSponsors,
                  variant: WpButtonVariant.primary,
                  autofocus: true,
                  onPressed: () => onResult(_SupportAction.gitHubSponsors),
                ),
                const SizedBox(height: WpSpacing.xs),
                WpButton(
                  label: l10n.aboutKofi,
                  variant: WpButtonVariant.secondary,
                  onPressed: () => onResult(_SupportAction.kofi),
                ),
                const SizedBox(height: WpSpacing.sm),
                WpButton(
                  label: l10n.reviewPromptNever,
                  variant: WpButtonVariant.ghost,
                  tone: WpButtonTone.neutral,
                  onPressed: () => onResult(_SupportAction.dismiss),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
