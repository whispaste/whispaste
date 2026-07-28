import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/settings_enums.dart';
import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/hotkey_service.dart';
import '../../../widgets/wp_accent_button.dart';
import '../../settings/settings_widgets.dart';

/// Widget keys exposed for testing. Kept in one place so tests and production
/// code agree on the contract.
@visibleForTesting
const kReadyStepAutostartToggleKey = Key('readyStepAutostartToggle');
@visibleForTesting
const kReadyStepStartButtonKey = Key('readyStepStartButton');

/// Onboarding's final step — quick-start guide, an autostart toggle, and the
/// Start CTA.
///
/// Hotkey configuration (summary, rebind, conflict resolution) used to live
/// here; it moved to `TriggerStep`, which now runs earlier in the flow, right
/// before the guided test recording. This step no longer configures
/// anything hotkey-related — it keeps only a residual safety gate: if the
/// hotkey is a confirmed conflict (e.g. the user skipped past `TriggerStep`'s
/// warning), Start stays disabled rather than sending the user into a
/// non-functional hotkey.
class ReadyStep extends ConsumerWidget {
  const ReadyStep({super.key, required this.onComplete, required this.onBack});

  final VoidCallback onComplete;
  final VoidCallback onBack;

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
    final accentGradient = isDark
        ? WpColorsDark.accentWarmGradient
        : WpColorsLight.accentWarmGradient;
    final surfaceVariant =
        (isDark ? WpColorsDark.surfaceVariant : WpColorsLight.surfaceVariant)
            .withValues(alpha: 0.55);
    final borderColor = isDark
        ? WpColorsDark.borderSubtle
        : WpColorsLight.borderSubtle;

    // Start CTA is gated on a healthy hotkey registration. `unknown` keeps
    // the button enabled — the registration runs in the background and the
    // user shouldn't be blocked by a transient race during the very first
    // mount; only a confirmed `conflict` disables Start. This is a residual
    // safety net for a conflict the user skipped past in `TriggerStep`.
    final startEnabled = status != HotkeyRegistrationStatus.conflict;

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

        // Residual conflict notice — TriggerStep is the place to fix this;
        // here it's just a short heads-up next to the (disabled) Start CTA.
        if (!startEnabled) ...[
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
        // xl (not xxl) before the autostart card: it groups the optional
        // toggle with the quickstart block above it and keeps the card
        // subordinate to the Start CTA — the step's real focal point.
        const SizedBox(height: WpSpacing.xl),

        // Autostart toggle — a simpler yes/no than Settings → Interface's
        // never/normal/minimized dropdown; picking "yes" here always means
        // normal (not minimized) startup. `startMinimized` keeps its default
        // (`false`); the full dropdown remains available later in Settings.
        Container(
          decoration: BoxDecoration(
            color: surfaceVariant,
            borderRadius: WpRadius.borderLg,
            border: Border.all(color: borderColor),
          ),
          padding: const EdgeInsets.symmetric(horizontal: WpSpacing.sm),
          child: SettingRow(
            key: kReadyStepAutostartToggleKey,
            icon: LucideIcons.power,
            label: l10n.onboardingReadyAutostartToggle,
            subtitle: l10n.onboardingReadyAutostartToggleHint,
            semanticToggledValue: settings.launchAtStartup,
            trailing: settingsToggle(
              value: settings.launchAtStartup,
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .updateSettings((s) => s.copyWith(launchAtStartup: v)),
            ),
          ),
        ),
        const SizedBox(height: WpSpacing.xxl),

        // Navigation row
        Row(
          children: [
            TextButton(
              onPressed: onBack,
              child: Text(
                l10n.onboardingBack,
                style: TextStyle(
                  color: textMuted,
                  fontSize: WpTypography.subheading,
                ),
              ),
            ),
            const Spacer(),
            Expanded(
              flex: 2,
              // loam-ignore: a11y-interactive-semantics – semantics provided in WpAccentButton.build
              child: WpAccentButton(
                key: kReadyStepStartButtonKey,
                label: l10n.onboardingStartUsing,
                gradient: accentGradient,
                onPressed: startEnabled ? onComplete : null,
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
