import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/settings_enums.dart';
import '../../../core/config/settings_labels.dart';
import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/hotkey_service.dart';
import '../../../widgets/hotkey_recorder.dart';
import '../../../widgets/wp_accent_button.dart';

/// Widget keys exposed for testing. Kept in one place so tests and production
/// code agree on the contract.
@visibleForTesting
const kReadyStepConflictWarnBoxKey = Key('readyStepHotkeyConflictWarnBox');
@visibleForTesting
const kReadyStepInlineRecorderKey = Key('readyStepInlineHotkeyRecorder');
@visibleForTesting
const kReadyStepStartButtonKey = Key('readyStepStartButton');

/// Onboarding Step 4 — Ready screen with hotkey summary and quick-start guide.
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

    final hotkeyKey = settings.hotkeyKey;
    final hotkeyDisplay = settings.hotkey.hotkeyKeyDisplay;
    final hotkeyModifiers = settings.hotkeyModifiers;
    final modifierLabels = hotkeyModifierLabels(hotkeyModifiers, l10n: l10n);
    final keyCapLabel = hotkeyDisplay.trim().isNotEmpty
        ? (hotkeyDisplay.length == 1
              ? hotkeyDisplay.toUpperCase()
              : hotkeyDisplay)
        : hotkeyKey;
    final formattedHotkey = formatHotkeyShortcut(
      hotkeyModifiers,
      hotkeyKey,
      l10n: l10n,
      displayOverride: hotkeyDisplay,
    );

    // Start CTA is gated on a healthy hotkey registration. `unknown` keeps
    // the button enabled — the registration runs in the background and the
    // user shouldn't be blocked by a transient race during the very first
    // mount; only a confirmed `conflict` disables Start.
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
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: textPrimary,
          ),
        ),
        const SizedBox(height: WpSpacing.xs),

        // Subtitle
        Text(
          l10n.onboardingReadySubtitle,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: textSecondary),
        ),
        const SizedBox(height: WpSpacing.xxl),

        // Hotkey display — branches on the registration status so a confirmed
        // conflict surfaces a warning + inline rebind UI BEFORE the user can
        // click Start.
        if (status == HotkeyRegistrationStatus.conflict) ...[
          _HotkeyConflictWarnBox(
            key: kReadyStepConflictWarnBoxKey,
            title: l10n.onboardingReadyHotkeyConflictTitle,
            body: l10n.onboardingReadyHotkeyConflictBody,
            isDark: isDark,
          ),
          const SizedBox(height: WpSpacing.md),
          // Inline recorder: same widget as the Settings modal, but with an
          // `onSubmit` callback so it stays mounted and the parent owns the
          // result. Persisting the new combo triggers `hotkey_service`'s
          // settings listener, which calls `updateHotkey` and flips the
          // status back to `success` (or `conflict` again if the new combo
          // also fails — at which point the user can rebind once more).
          HotkeyRecorderDialog(
            key: kReadyStepInlineRecorderKey,
            initialKey: hotkeyKey,
            initialDisplayKey: hotkeyDisplay,
            initialModifiers: hotkeyModifiers,
            onSubmit: (result) async {
              await ref
                  .read(settingsProvider.notifier)
                  .updateSettings(
                    (s) => s.copyWith(
                      hotkeyKey: result.key,
                      hotkeyKeyDisplay: result.displayKey,
                      hotkeyModifiers: result.modifiers,
                    ),
                  );
            },
          ),
          const SizedBox(height: WpSpacing.xl),
        ] else ...[
          Text(
            l10n.onboardingReadyCurrentHotkey,
            style: TextStyle(fontSize: 12, color: textMuted),
          ),
          const SizedBox(height: WpSpacing.sm),
          Semantics(
            label: '${l10n.onboardingReadyCurrentHotkey}: $formattedHotkey',
            child: _HotkeyKeyCaps(
              modifiers: modifierLabels,
              keyLabel: keyCapLabel,
              isDark: isDark,
            ),
          ),
          const SizedBox(height: WpSpacing.sm),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () async {
                final result = await HotkeyRecorderDialog.show(
                  context,
                  initialKey: hotkeyKey,
                  initialDisplayKey: hotkeyDisplay,
                  initialModifiers: hotkeyModifiers,
                );
                if (result != null && context.mounted) {
                  await ref
                      .read(settingsProvider.notifier)
                      .updateSettings(
                        (s) => s.copyWith(
                          hotkeyKey: result.key,
                          hotkeyKeyDisplay: result.displayKey,
                          hotkeyModifiers: result.modifiers,
                        ),
                      );
                }
              },
              borderRadius: WpRadius.borderSm,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: WpSpacing.sm,
                  vertical: WpSpacing.xs,
                ),
                child: Text(
                  l10n.onboardingReadyChangeHotkey,
                  style: TextStyle(
                    fontSize: 13,
                    color: accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: WpSpacing.xl),
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
        const SizedBox(height: WpSpacing.xxl),

        // Navigation row
        Row(
          children: [
            TextButton(
              onPressed: onBack,
              child: Text(
                l10n.onboardingBack,
                style: TextStyle(color: textMuted, fontSize: 14),
              ),
            ),
            const Spacer(),
            Expanded(
              flex: 2,
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
// Hotkey key caps row — modifier pills + "+" separators + primary key
// ---------------------------------------------------------------------------

class _HotkeyKeyCaps extends StatelessWidget {
  const _HotkeyKeyCaps({
    required this.modifiers,
    required this.keyLabel,
    required this.isDark,
  });

  final List<String> modifiers;
  final String keyLabel;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final textMuted = isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
    final surfaceVariant = isDark
        ? WpColorsDark.surfaceVariant
        : WpColorsLight.surfaceVariant;
    final borderColor = isDark
        ? WpColorsDark.borderSubtle
        : WpColorsLight.borderSubtle;
    final textPrimary = isDark
        ? WpColorsDark.textPrimary
        : WpColorsLight.textPrimary;

    final caps = <Widget>[];
    for (var i = 0; i < modifiers.length; i++) {
      if (i > 0) {
        caps.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: WpSpacing.xxs),
            child: Text(
              '+',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: textMuted,
              ),
            ),
          ),
        );
      }
      caps.add(
        _KeyCapPill(
          label: modifiers[i],
          bgColor: surfaceVariant,
          borderColor: borderColor,
          textColor: textPrimary,
        ),
      );
    }

    if (keyLabel.isNotEmpty) {
      if (caps.isNotEmpty) {
        caps.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: WpSpacing.xxs),
            child: Text(
              '+',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: textMuted,
              ),
            ),
          ),
        );
      }
      caps.add(
        _KeyCapPill(
          label: keyLabel,
          bgColor: surfaceVariant,
          borderColor: borderColor,
          textColor: textPrimary,
        ),
      );
    }

    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: WpSpacing.xxs,
      runSpacing: WpSpacing.xs,
      children: caps,
    );
  }
}

class _KeyCapPill extends StatelessWidget {
  const _KeyCapPill({
    required this.label,
    required this.bgColor,
    required this.borderColor,
    required this.textColor,
  });

  final String label;
  final Color bgColor;
  final Color borderColor;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: WpSpacing.sm,
        vertical: WpSpacing.xxs + 2,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(WpRadius.sm),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: textColor,
          letterSpacing: 0.3,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
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
              style: TextStyle(fontSize: 14, color: textColor),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hotkey conflict warn-box — red banner shown in the `conflict` branch.
// ---------------------------------------------------------------------------

class _HotkeyConflictWarnBox extends StatelessWidget {
  const _HotkeyConflictWarnBox({
    super.key,
    required this.title,
    required this.body,
    required this.isDark,
  });

  final String title;
  final String body;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    // Use the theme's danger/error semantic so the box clearly reads as a
    // blocker — matches the rest of WhisPaste's destructive surfaces.
    final dangerColor = isDark ? WpColorsDark.error : WpColorsLight.error;
    final bgColor = dangerColor.withValues(alpha: isDark ? 0.12 : 0.10);
    final borderColor = dangerColor.withValues(alpha: isDark ? 0.40 : 0.32);
    final textPrimary = isDark
        ? WpColorsDark.textPrimary
        : WpColorsLight.textPrimary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: WpSpacing.md,
        vertical: WpSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(WpRadius.sm),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            LucideIcons.triangleAlert,
            size: WpIconSize.md,
            color: dangerColor,
          ),
          const SizedBox(width: WpSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: dangerColor,
                  ),
                ),
                const SizedBox(height: WpSpacing.xxs),
                Text(
                  body,
                  style: TextStyle(
                    fontSize: 12,
                    color: textPrimary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
