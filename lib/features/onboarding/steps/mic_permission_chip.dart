/// Ambient microphone permission status chip (onboarding page 1).
///
/// Replaces the old full-screen `MicrophoneStep` probe: this chip only
/// answers "may WhisPaste use the microphone?" by consuming
/// [MicPermissionNotifier] — no live audio, no waveform, no device picker
/// (the device choice lives in Settings → Recording). The "does it actually
/// work?" question is answered later, by the guided test recording on page 5.
///
/// One platform-independent vocabulary, three states:
///   ready (granted) / pending (unknown or requesting) / action needed
///   (denied). A fresh install must never read "action needed" before the
///   first request — `unknown` maps to pending by design.
///
/// Tapping ALWAYS calls [MicPermissionNotifier.request]: the notifier itself
/// decides between the one-time OS dialog and the Settings deep-link + poll
/// recovery path, so the widget carries no denied-handling of its own.
///
/// Hidden entirely on Linux: there is no Settings deep-link there, and the
/// chip must not promise an action the platform cannot deliver.
library;

import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/permissions/mic_permission_notifier.dart';

class MicPermissionChip extends ConsumerStatefulWidget {
  const MicPermissionChip({super.key});

  @override
  ConsumerState<MicPermissionChip> createState() => _MicPermissionChipState();
}

class _MicPermissionChipState extends ConsumerState<MicPermissionChip> {
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    // Side-effect-free status read only — never request() on appear. The OS
    // permission dialog fires either on an explicit tap or when *leaving*
    // page 1 (shell-owned, see `_goNext` in onboarding_overlay.dart); firing
    // it on appear would blow up the brand/demo moment with a modal.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (defaultTargetPlatform == TargetPlatform.linux) return;
      unawaited(ref.read(micPermissionNotifierProvider.notifier).check());
    });
  }

  @override
  Widget build(BuildContext context) {
    // No chip on Linux — the status alone would work, but the tap promises
    // a recovery action (Settings deep-link) that does not exist there.
    if (defaultTargetPlatform == TargetPlatform.linux) {
      return const SizedBox.shrink();
    }

    final l10n = L10n.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final status = ref.watch(micPermissionNotifierProvider).status;

    final surface =
        (isDark ? WpColorsDark.surfaceVariant : WpColorsLight.surfaceVariant)
            .withValues(alpha: 0.55);
    final hover = isDark ? WpColorsDark.hover : WpColorsLight.hover;
    final border = isDark
        ? WpColorsDark.borderSubtle
        : WpColorsLight.borderSubtle;
    final textPrimary = isDark
        ? WpColorsDark.textPrimary
        : WpColorsLight.textPrimary;

    // Status is carried by the tinted leading glyph and the copy — the pill
    // itself stays neutral (same quiet register as the Auto-Paste indicator).
    final (String label, IconData? icon, Color statusColor) = switch (status) {
      MicPermissionStatus.granted => (
        l10n.onboardingMicChipReady,
        LucideIcons.circleCheck,
        isDark ? WpColorsDark.success : WpColorsLight.success,
      ),
      MicPermissionStatus.denied => (
        l10n.onboardingMicChipAction,
        LucideIcons.shieldAlert,
        isDark ? WpColorsDark.warning : WpColorsLight.warning,
      ),
      // unknown & requesting both read "pending": a fresh install has simply
      // not been asked yet and must never claim "action needed".
      MicPermissionStatus.unknown || MicPermissionStatus.requesting => (
        l10n.onboardingMicChipPending,
        status == MicPermissionStatus.requesting ? null : LucideIcons.mic,
        isDark ? WpColorsDark.accent : WpColorsLight.accent,
      ),
    };

    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          // Always request() — the notifier alone decides between the real
          // one-time OS dialog and the Settings deep-link + poll recovery.
          onTap: () => unawaited(
            ref.read(micPermissionNotifierProvider.notifier).request(),
          ),
          borderRadius: WpRadius.borderFull,
          onHover: (hovering) => setState(() => _hovered = hovering),
          child: AnimatedContainer(
            duration: WpMotion.durationFor(context, WpMotion.fast),
            curve: WpMotion.defaultCurve,
            padding: const EdgeInsets.symmetric(
              horizontal: WpSpacing.md,
              vertical: WpSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: _hovered ? hover : surface,
              borderRadius: WpRadius.borderFull,
              border: Border.all(color: border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSwitcher(
                  duration: WpMotion.durationFor(context, WpMotion.fast),
                  child: icon == null
                      ? SizedBox(
                          key: const ValueKey('micChipSpinner'),
                          width: WpIconSize.sm,
                          height: WpIconSize.sm,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: statusColor,
                          ),
                        )
                      : Icon(
                          icon,
                          key: ValueKey(icon),
                          size: WpIconSize.sm,
                          color: statusColor,
                        ),
                ),
                const SizedBox(width: WpSpacing.xs),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: WpTypography.body,
                    fontWeight: FontWeight.w600,
                    color: textPrimary,
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
