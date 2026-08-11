/// Store thank-you hint watcher and dialog.
///
/// [WpStoreThankYouWatcher] listens for the right moment to surface a
/// one-time, discreet "Danke für deine Unterstützung" overlay shown to
/// Store-channel users after their onboarding completes.
///
/// Gating conditions (enforced by [StoreThankYouNotifier]):
///   - Deploy channel is [DeployChannel.store].
///   - The SharedPreferences flag is not yet set.
///   - The onboarding surface is not on top — onboarding has been completed
///     and the five-step flow is not currently reopened from Settings.
///
/// CTA URLs: single-source constants [kWindowsStoreReviewUrl] (Windows only)
/// and [kGitHubRepoUrl] — no hardcoded literals. On macOS/Linux no reliable
/// store review deep-link exists, so only the GitHub star CTA is shown
/// (mirrors the review prompt dialog's platform split).
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_urls.dart';
import '../core/config/settings_provider.dart';
import '../core/l10n/generated/app_localizations.dart';
import '../core/onboarding/onboarding_surface.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import '../services/store_thank_you_service.dart';
import 'wp_button.dart';

/// Override for testing. When non-null, [WpStoreThankYouWatcher] uses this
/// value instead of [Platform.isWindows].
///
/// Wp naming — deliberately unprefixed, same reasoning as
/// [platformIsWindowsOverride] in `review_prompt_dialog.dart`:
/// `@visibleForTesting` seams stay outside the component vocabulary.
@visibleForTesting
bool? storeThankYouPlatformIsWindowsOverride;

// ---------------------------------------------------------------------------
// Watcher (public entry point)
// ---------------------------------------------------------------------------

/// Listens for the moment to show the one-time store thank-you hint.
///
/// Triggers [StoreThankYouNotifier.checkAndMaybeShow] once onboarding is
/// done — either already completed when this widget mounts (returning users),
/// or the instant [AppSettings.onboarding.onboardingCompleted] flips to
/// `true` in the current session (first-run users).
///
/// Place this widget anywhere above the content layer (e.g., wrapping
/// [WpServiceBootstrap]).  It renders no visible UI of its own.
class WpStoreThankYouWatcher extends ConsumerStatefulWidget {
  const WpStoreThankYouWatcher({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<WpStoreThankYouWatcher> createState() =>
      _WpStoreThankYouWatcherState();
}

class _WpStoreThankYouWatcherState
    extends ConsumerState<WpStoreThankYouWatcher> {
  Timer? _delay;
  bool _dialogShowing = false;

  bool get _isWindows =>
      storeThankYouPlatformIsWindowsOverride ?? Platform.isWindows;

  @override
  void initState() {
    super.initState();
    // Check on first mount — handles returning users whose onboarding was
    // already completed in a previous session.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final onboarded =
          ref.read(settingsProvider).value?.onboarding.onboardingCompleted ??
          false;
      _triggerCheck(onboarded);
    });
  }

  @override
  void dispose() {
    _delay?.cancel();
    super.dispose();
  }

  Future<void> _triggerCheck(bool onboardingCompleted) async {
    await ref
        .read(storeThankYouProvider.notifier)
        .checkAndMaybeShow(onboardingCompleted: onboardingCompleted);
  }

  void _maybeShow(StoreThankYouState state, BuildContext context) {
    if (!state.shouldShow || _dialogShowing) return;
    // The notifier already gated on "is the onboarding surface on top", but
    // it decided that at *check* time and this runs at *show* time, two
    // seconds later. Re-asking the two halves that can flip in between — the
    // user opening a review from Settings, or a revision run starting —
    // closes that window. The completed half stays the notifier's: it is
    // answered against the caller's own settings snapshot, which is what
    // makes the first-run hand-off work at the exact moment the flag flips.
    // Nothing is latched here, so the next check re-offers the hint once the
    // review or run ends.
    if (ref.read(onboardingManuallyOpenProvider) ||
        ref.read(onboardingRevisionRunProvider)) {
      return;
    }
    _dialogShowing = true;
    // A short delay after onboarding exit so the overlay animation has
    // settled before the hint appears.
    _delay = Timer(const Duration(seconds: 2), () {
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
      transitionDuration: WpMotion.durationFor(context, WpMotion.smooth),
      pageBuilder: (_, p1, p2) => const SizedBox.shrink(),
      transitionBuilder: (ctx, animation, p1, p2) {
        final opacity = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOut,
        );
        return FadeTransition(
          opacity: opacity,
          child: Stack(
            children: [
              Positioned.fill(child: ColoredBox(color: wpDialogBarrierColor())),
              _StoreThankYouDialog(
                animation: animation,
                isWindows: _isWindows,
                onDismiss: () async {
                  Navigator.of(ctx).pop();
                  await _markDone();
                },
                onRateStore: () async {
                  Navigator.of(ctx).pop();
                  await _markDone();
                  await _launchUrl(kWindowsStoreReviewUrl);
                },
                onStarGitHub: () async {
                  Navigator.of(ctx).pop();
                  await _markDone();
                  await _launchUrl(kGitHubRepoUrl);
                },
              ),
            ],
          ),
        );
      },
    );
    // Safety net: ensure the flag is persisted even when the dialog is closed
    // via barrier tap (no explicit button was pressed).
    await _markDone();
    _dialogShowing = false;
  }

  Future<void> _markDone() =>
      ref.read(storeThankYouProvider.notifier).markShown();

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watch for onboarding completion during the current session (first-run).
    ref.listen<AsyncValue<AppSettings>>(settingsProvider, (prev, next) {
      final wasCompleted = prev?.value?.onboarding.onboardingCompleted ?? false;
      final isCompleted = next.value?.onboarding.onboardingCompleted ?? false;
      if (!wasCompleted && isCompleted) {
        _triggerCheck(true);
      }
    });

    // Watch for the show signal emitted by the notifier.
    ref.listen<StoreThankYouState>(storeThankYouProvider, (_, next) {
      _maybeShow(next, context);
    });

    return widget.child;
  }
}

// ---------------------------------------------------------------------------
// Dialog widget (package-private)
// ---------------------------------------------------------------------------

class _StoreThankYouDialog extends StatelessWidget {
  const _StoreThankYouDialog({
    required this.animation,
    required this.isWindows,
    required this.onDismiss,
    required this.onRateStore,
    required this.onStarGitHub,
  });

  final Animation<double> animation;
  final bool isWindows;
  final VoidCallback onDismiss;
  final VoidCallback onRateStore;
  final VoidCallback onStarGitHub;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);

    final slide = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut));

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
                  l10n.storeThankYouTitle,
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: WpSpacing.sm),
                Text(
                  l10n.storeThankYouBody,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: WpColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: WpSpacing.lg),
                // Windows: Store-review CTA + GitHub star. macOS/Linux: no
                // reliable store review deep-link exists — only the GitHub
                // star CTA (mirrors the review prompt dialog).
                if (isWindows) ...[
                  WpButton(
                    label: l10n.storeThankYouCtaStore,
                    variant: WpButtonVariant.primary,
                    autofocus: true,
                    onPressed: onRateStore,
                  ),
                  const SizedBox(height: WpSpacing.xs),
                  WpButton(
                    label: l10n.storeThankYouCtaGitHub,
                    variant: WpButtonVariant.secondary,
                    onPressed: onStarGitHub,
                  ),
                ] else
                  WpButton(
                    label: l10n.storeThankYouCtaGitHub,
                    variant: WpButtonVariant.primary,
                    autofocus: true,
                    onPressed: onStarGitHub,
                  ),
                const SizedBox(height: WpSpacing.sm),
                WpButton(
                  label: l10n.storeThankYouDismiss,
                  variant: WpButtonVariant.ghost,
                  tone: WpButtonTone.neutral,
                  onPressed: onDismiss,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
