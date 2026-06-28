/// Store thank-you hint watcher and dialog.
///
/// [StoreThankYouWatcher] listens for the right moment to surface a
/// one-time, discreet "Danke für deine Unterstützung" overlay shown to
/// Store-channel users after their onboarding completes.
///
/// Gating conditions (enforced by [StoreThankYouNotifier]):
///   - Deploy channel is [DeployChannel.store].
///   - The SharedPreferences flag is not yet set.
///   - Onboarding has been completed.
///
/// CTA URLs: single-source constants [kWindowsStoreReviewUrl] and
/// [kGitHubRepoUrl] — no hardcoded literals.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_urls.dart';
import '../core/config/settings_provider.dart';
import '../core/l10n/generated/app_localizations.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import '../services/store_thank_you_service.dart';

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
/// [ServiceBootstrapWidget]).  It renders no visible UI of its own.
class StoreThankYouWatcher extends ConsumerStatefulWidget {
  const StoreThankYouWatcher({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<StoreThankYouWatcher> createState() =>
      _StoreThankYouWatcherState();
}

class _StoreThankYouWatcherState extends ConsumerState<StoreThankYouWatcher> {
  Timer? _delay;
  bool _dialogShowing = false;

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
              _StoreThankYouDialog(
                animation: animation,
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
    required this.onDismiss,
    required this.onRateStore,
    required this.onStarGitHub,
  });

  final Animation<double> animation;
  final VoidCallback onDismiss;
  final VoidCallback onRateStore;
  final VoidCallback onStarGitHub;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

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
                  l10n.storeThankYouTitle,
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: WpSpacing.sm),
                Text(
                  l10n.storeThankYouBody,
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
                  onPressed: onRateStore,
                  child: Text(l10n.storeThankYouCtaStore),
                ),
                const SizedBox(height: WpSpacing.xs),
                OutlinedButton(
                  onPressed: onStarGitHub,
                  child: Text(l10n.storeThankYouCtaGitHub),
                ),
                const SizedBox(height: WpSpacing.sm),
                TextButton(
                  onPressed: onDismiss,
                  child: Text(
                    l10n.storeThankYouDismiss,
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
