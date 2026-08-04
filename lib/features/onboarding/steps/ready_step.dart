import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/settings_enums.dart';
import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/hotkey_service.dart';

/// Closing content of the final onboarding page — quick-start guide and the
/// residual hotkey-conflict notice.
///
/// The autostart toggle that used to live here moved to the
/// Autostart & Auto-Paste page ([OnboardingAutostartToggle]); the Start CTA
/// and Back navigation are owned by the onboarding shell, which keeps the
/// residual safety gate: with a confirmed hotkey conflict the completion CTA
/// stays disabled rather than sending the user into a non-functional hotkey.
/// This widget only renders the matching heads-up text next to that gate.
class ReadyStep extends ConsumerWidget {
  const ReadyStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
    final status = ref.watch(hotkeyRegistrationStatusProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = L10n.of(context);

    final accent = isDark ? WpColorsDark.accent : WpColorsLight.accent;
    final textPrimary = isDark
        ? WpColorsDark.textPrimary
        : WpColorsLight.textPrimary;
    final textSecondary = isDark
        ? WpColorsDark.textSecondary
        : WpColorsLight.textSecondary;
    final textMuted = isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;

    // The completion CTA (owned by the onboarding shell) is gated on a healthy
    // hotkey registration; this content mirrors that gate with a short
    // heads-up so the disabled CTA never appears unexplained.
    final hasConflict = status == HotkeyRegistrationStatus.conflict;

    // Auto-Paste is active when `afterTranscription` is set to `paste` or
    // `clipboard_and_paste` — both inject the transcript at the cursor. The
    // other two states (`clipboard`, `nothing`) leave the user to paste with
    // ⌘V / Ctrl+V themselves, so step 3 must spell that out.
    final autoPasteAfterTranscription =
        switch (settings.afterTranscriptionAction) {
          AfterTranscriptionAction.paste ||
          AfterTranscriptionAction.clipboardAndPaste => true,
          AfterTranscriptionAction.clipboard ||
          AfterTranscriptionAction.nothing => false,
        };
    final step3Text = autoPasteAfterTranscription
        ? l10n.onboardingReadyStep3AutoPaste
        : l10n.onboardingReadyStep3CopyOnly;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Title
        Text(
          l10n.onboardingReadyTitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: WpTypography.headline,
            fontWeight: FontWeight.bold,
            color: textPrimary,
          ),
        ),
        const SizedBox(height: WpSpacing.xs),

        // Subtitle
        Text(
          l10n.onboardingReadySubtitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: WpTypography.subheading,
            color: textSecondary,
          ),
        ),
        const SizedBox(height: WpSpacing.xxl),

        // Residual conflict notice — the Model & Hotkey page is the place to
        // fix this; here it's just a short heads-up explaining the disabled
        // completion CTA.
        if (hasConflict) ...[
          Text(
            l10n.onboardingTriggerHotkeyConflictTitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: WpTypography.small,
              fontWeight: FontWeight.w600,
              color: isDark ? WpColorsDark.error : WpColorsLight.error,
            ),
          ),
          const SizedBox(height: WpSpacing.md),
        ],

        // Quick start instructions
        _InstructionRow(
          number: '1.',
          text: l10n.onboardingReadyStep1,
          icon: LucideIcons.keyboard,
          accent: accent,
          textColor: textPrimary,
        ),
        const SizedBox(height: WpSpacing.md),
        _InstructionRow(
          number: '2.',
          text: l10n.onboardingReadyStep2,
          icon: LucideIcons.micOff,
          accent: accent,
          textColor: textPrimary,
        ),
        const SizedBox(height: WpSpacing.md),
        _InstructionRow(
          number: '3.',
          text: step3Text,
          icon: LucideIcons.clipboard,
          accent: accent,
          textColor: textPrimary,
        ),

        // Context-carryover side note — deliberately NOT a fourth numbered
        // step (it's a tip, not part of the core loop). Mirrors the muted
        // hint style of the recording-duration note on the Model & Hotkey
        // page (appearance_section.dart).
        const SizedBox(height: WpSpacing.lg),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(LucideIcons.info, size: 14, color: textMuted),
            ),
            const SizedBox(width: WpSpacing.xs),
            Expanded(
              child: Text(
                l10n.onboardingReadyContextCarryoverHint,
                style: TextStyle(
                  fontSize: WpTypography.small,
                  color: textMuted,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Instruction row — numbered step with icon
// ---------------------------------------------------------------------------

class _InstructionRow extends StatelessWidget {
  const _InstructionRow({
    required this.number,
    required this.text,
    required this.icon,
    required this.accent,
    required this.textColor,
  });

  final String number;
  final String text;
  final IconData icon;
  final Color accent;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      excludeSemantics: true,
      label: '$number $text',
      child: Row(
        children: [
          Icon(icon, size: WpIconSize.md, color: accent),
          const SizedBox(width: WpSpacing.sm),
          Expanded(
            child: Text(
              '$number $text',
              style: TextStyle(
                fontSize: WpTypography.subheading,
                color: textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
