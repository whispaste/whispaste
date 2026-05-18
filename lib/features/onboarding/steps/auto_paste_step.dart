/// Onboarding Step 3 — Auto-Paste permission setup.
///
/// On macOS: walks the user through granting the Accessibility permission
/// so Auto-Paste can simulate ⌘V into the focused window. Watches the
/// shared [PasteCapabilityNotifier] for state, opens the macOS Settings
/// panel via the standard `x-apple.systempreferences:` deep link, and
/// polls for the capability to flip to [PasteCapabilityStatus.ready] while
/// the user toggles the setting in System Settings.
///
/// On Windows: this slice still renders the same macOS-shaped flow as a
/// placeholder; slice 05 will replace it with a dedicated verify-only path.
///
/// On Linux: never rendered — [OnboardingOverlay] omits the step entirely
/// from its platform-dependent step list.
///
/// The Skip path persists `afterTranscription = clipboard` (the codebase's
/// representation of "Auto-Paste off, copy still happens") and advances
/// the onboarding overlay via [onNext]. Polling is stopped on dispose so
/// there is never a leftover timer once the user leaves the step.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/settings_enums.dart';
import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/paste/paste_capability_notifier.dart';
import '../../../services/paste/paster.dart';
import '../../../widgets/wp_accent_button.dart';

class AutoPasteStep extends ConsumerStatefulWidget {
  const AutoPasteStep({super.key, required this.onNext, required this.onBack});

  final VoidCallback onNext;
  final VoidCallback onBack;

  @override
  ConsumerState<AutoPasteStep> createState() => _AutoPasteStepState();
}

class _AutoPasteStepState extends ConsumerState<AutoPasteStep> {
  static final _log = AppLogger('AutoPasteStep');

  /// Cached notifier reference so [dispose] can stop polling without
  /// touching `ref` — Riverpod forbids `ref` access after deactivation.
  PasteCapabilityNotifier? _cachedNotifier;

  @override
  void initState() {
    super.initState();
    // Probe once on mount without prompting so the UI immediately reflects
    // the current OS state. The shared notifier handles in-flight coalescing.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _cachedNotifier = ref.read(pasteCapabilityNotifierProvider.notifier);
      _cachedNotifier!.check();
    });
  }

  @override
  void dispose() {
    // Polling lives in the shared notifier; stop it explicitly when the user
    // leaves the step so we don't keep a timer alive after navigation.
    // Use the cached reference because `ref` is unsafe in dispose().
    _cachedNotifier?.stopPolling();
    super.dispose();
  }

  Future<void> _openAccessibilitySettings() async {
    if (!Platform.isMacOS) return;
    final uri = Uri.parse(
      'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility',
    );
    try {
      await launchUrl(uri);
    } on Exception catch (e) {
      _log.warning('Could not open Accessibility settings', e);
    }
  }

  Future<void> _onGrantPressed() async {
    final notifier = ref.read(pasteCapabilityNotifierProvider.notifier);
    // First fire the prompted check so macOS gets a chance to surface its
    // own one-shot dialog. Then deep-link to the Accessibility pane so the
    // user sees the toggle row even if the OS dialog was suppressed.
    await notifier.check(prompt: true);
    await _openAccessibilitySettings();
    notifier.startPolling(
      interval: const Duration(seconds: 1),
      timeout: const Duration(seconds: 30),
    );
  }

  Future<void> _onSkipPressed() async {
    // Skip explicitly disables Auto-Paste rather than silently leaving the
    // user in a half-state. "clipboard" is the codebase's encoding for
    // "transcript goes to clipboard, no automated paste".
    await ref
        .read(settingsProvider.notifier)
        .updateSettings(
          (s) => s.copyWith(
            afterTranscription: AfterTranscriptionAction.clipboard.value,
          ),
        );
    widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = L10n.of(context);
    final state = ref.watch(pasteCapabilityNotifierProvider);
    final notifier = ref.read(pasteCapabilityNotifierProvider.notifier);
    _cachedNotifier = notifier;
    final cap = state.capability;
    final isReady = cap?.status == PasteCapabilityStatus.ready;

    final textPrimary = isDark
        ? WpColorsDark.textPrimary
        : WpColorsLight.textPrimary;
    final textSecondary = isDark
        ? WpColorsDark.textSecondary
        : WpColorsLight.textSecondary;
    final textMuted = isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
    final accentGradient = isDark
        ? WpColorsDark.accentWarmGradient
        : WpColorsLight.accentWarmGradient;
    final successColor = isDark ? WpColorsDark.success : WpColorsLight.success;
    final errorColor = isDark ? WpColorsDark.error : WpColorsLight.error;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // -- Title ----------------------------------------------------------
        Text(
          l10n.onboardingPasteTitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: textPrimary,
          ),
        ),
        const SizedBox(height: WpSpacing.xs),
        Text(
          l10n.onboardingPasteSubtitle,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: textSecondary, height: 1.4),
        ),
        const SizedBox(height: WpSpacing.xl),

        // -- Permission status card ----------------------------------------
        _PermissionStatusCard(
          status: cap?.status,
          isPolling: notifier.isPolling,
          isDark: isDark,
          textPrimary: textPrimary,
          textSecondary: textSecondary,
          successColor: successColor,
          errorColor: errorColor,
          l10n: l10n,
        ),
        const SizedBox(height: WpSpacing.lg),

        // -- Grant CTA -- only shown until permission is ready --------------
        if (!isReady) ...[
          SizedBox(
            width: double.infinity,
            child: WpAccentButton(
              label: l10n.onboardingPasteGrantCta,
              gradient: accentGradient,
              onPressed: _onGrantPressed,
            ),
          ),
          const SizedBox(height: WpSpacing.sm),
          Text(
            l10n.onboardingPasteWhyMac,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: textMuted, height: 1.4),
          ),
          const SizedBox(height: WpSpacing.sm),
          // Skip — sets afterTranscription=clipboard and advances.
          TextButton(
            onPressed: _onSkipPressed,
            child: Text(
              l10n.onboardingPasteSkip,
              style: TextStyle(color: textSecondary, fontSize: 13),
            ),
          ),
        ],

        const SizedBox(height: WpSpacing.lg),

        // -- Navigation row -------------------------------------------------
        Row(
          children: [
            TextButton(
              onPressed: widget.onBack,
              child: Text(
                l10n.onboardingBack,
                style: TextStyle(color: textSecondary),
              ),
            ),
            const Spacer(),
            SizedBox(
              width: 140,
              child: WpAccentButton(
                label: l10n.onboardingNext,
                gradient: accentGradient,
                onPressed: isReady ? widget.onNext : null,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PermissionStatusCard extends StatelessWidget {
  const _PermissionStatusCard({
    required this.status,
    required this.isPolling,
    required this.isDark,
    required this.textPrimary,
    required this.textSecondary,
    required this.successColor,
    required this.errorColor,
    required this.l10n,
  });

  final PasteCapabilityStatus? status;
  final bool isPolling;
  final bool isDark;
  final Color textPrimary;
  final Color textSecondary;
  final Color successColor;
  final Color errorColor;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = _resolve();
    final surface =
        (isDark ? WpColorsDark.surfaceVariant : WpColorsLight.surfaceVariant)
            .withValues(alpha: 0.5);
    final border = isDark
        ? WpColorsDark.borderSubtle
        : WpColorsLight.borderSubtle;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: WpSpacing.md,
        vertical: WpSpacing.md,
      ),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: WpRadius.borderMd,
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 22, color: color),
          const SizedBox(width: WpSpacing.sm),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: textPrimary,
              ),
            ),
          ),
          if (isPolling)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }

  (IconData, Color, String) _resolve() {
    if (status == null) {
      return (
        LucideIcons.loaderCircle,
        textSecondary,
        l10n.pasteCapabilityCheckTitle,
      );
    }
    return switch (status!) {
      PasteCapabilityStatus.ready => (
        LucideIcons.circleCheck,
        successColor,
        l10n.pasteCapabilityReady,
      ),
      PasteCapabilityStatus.permissionMissing => (
        LucideIcons.shieldAlert,
        errorColor,
        l10n.pasteCapabilityPermissionMissing,
      ),
      PasteCapabilityStatus.unsupported => (
        LucideIcons.info,
        textSecondary,
        l10n.pasteCapabilityUnsupported,
      ),
    };
  }
}
