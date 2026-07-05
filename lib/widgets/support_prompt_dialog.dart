/// Support prompt dialog — surfaces a support/sponsor nudge mirroring the
/// structure of `review_prompt_dialog.dart`, but fully independent of it
/// (own provider, own watcher, own dismissal semantics).
///
/// Reuses the About page's existing support copy (`aboutSupportTitle` /
/// `aboutSupportDescription` / `aboutGitHubSponsors` / `aboutKofi`) so the
/// message stays consistent with the always-on support section, and reuses
/// `reviewPromptNever` for the dismiss action — its "never ask again" wording
/// applies generically and this prompt is dismissed permanently, matching
/// that semantic exactly.
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

// ---------------------------------------------------------------------------
// Public entry point
// ---------------------------------------------------------------------------

/// Listens to [supportPromptProvider] and shows the support dialog when
/// [SupportPromptState.shouldShowPrompt] becomes `true`.
///
/// Place this widget anywhere in the widget tree — it renders no visible UI
/// of its own and waits [kPostRecordingPromptDelay] before showing, so it
/// never interrupts a recording's completion moment.
class SupportPromptWatcher extends ConsumerStatefulWidget {
  const SupportPromptWatcher({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<SupportPromptWatcher> createState() =>
      _SupportPromptWatcherState();
}

class _SupportPromptWatcherState extends ConsumerState<SupportPromptWatcher> {
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
      _showDialog(context);
    });
  }

  Future<void> _showDialog(BuildContext context) async {
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
              _SupportPromptDialog(
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

  Future<void> _handleAction(_SupportAction action) async {
    final notifier = ref.read(supportPromptProvider.notifier);
    await notifier.markResolved();
    switch (action) {
      case _SupportAction.gitHubSponsors:
        await _launchUrl(kGitHubSponsorsUrl);
      case _SupportAction.kofi:
        await _launchUrl(kKofiUrl);
      case _SupportAction.dismiss:
        break;
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
  const _SupportPromptDialog({required this.animation, required this.onResult});

  final Animation<double> animation;
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
                  l10n.aboutSupportTitle,
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: WpSpacing.sm),
                Text(
                  l10n.aboutSupportDescription,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: isDark
                        ? WpColorsDark.textSecondary
                        : WpColorsLight.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: WpSpacing.lg),
                FilledButton(
                  autofocus: true,
                  onPressed: () => onResult(_SupportAction.gitHubSponsors),
                  child: Text(l10n.aboutGitHubSponsors),
                ),
                const SizedBox(height: WpSpacing.xs),
                OutlinedButton(
                  onPressed: () => onResult(_SupportAction.kofi),
                  child: Text(l10n.aboutKofi),
                ),
                const SizedBox(height: WpSpacing.sm),
                TextButton(
                  onPressed: () => onResult(_SupportAction.dismiss),
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
