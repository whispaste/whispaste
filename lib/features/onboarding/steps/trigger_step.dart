import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/hotkey_service.dart';
import '../../../services/telemetry_service.dart';
import '../../../widgets/hotkey_recorder.dart';
import '../../../widgets/wp_accent_button.dart';
import '../../settings/settings_widgets.dart';

/// Widget keys exposed for testing. Kept in one place so tests and production
/// code agree on the contract.
@visibleForTesting
const kTriggerStepChangeHotkeyKey = Key('triggerStepChangeHotkeyButton');
@visibleForTesting
const kTriggerStepPttToggleKey = Key('triggerStepPushToTalkToggle');
@visibleForTesting
const kTriggerStepConflictWarnBoxKey = Key('triggerStepHotkeyConflictWarnBox');
@visibleForTesting
const kTriggerStepInlineRecorderKey = Key('triggerStepInlineHotkeyRecorder');
@visibleForTesting
const kTriggerStepNextButtonKey = Key('triggerStepNextButton');

/// Onboarding step — how the user triggers a recording: the global hotkey,
/// and whether it's held (push-to-talk) or pressed-to-toggle.
///
/// Sits between [ModelStep] and `TestRecordingStep` so the guided test
/// recording immediately after this step exercises the real, just-configured
/// hotkey and mode — not a stale default the user hasn't seen yet. Previously
/// the hotkey summary/rebind lived in `ReadyStep`; it moved here so
/// configuration happens before the first real use, and `ReadyStep` becomes a
/// pure confirmation + start screen.
///
/// Both settings have valid defaults (`Ctrl/Cmd+Shift+D`, toggle mode), so
/// this step is always skippable — advancing without changing anything is a
/// legitimate choice, not a partial state. The one exception is a confirmed
/// hotkey conflict: `ReadyStep` keeps a residual gate on its Start button for
/// the case where the user skips past an unresolved conflict here.
class TriggerStep extends ConsumerWidget {
  const TriggerStep({super.key, required this.onNext, required this.onBack});

  final VoidCallback onNext;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
    final status = ref.watch(hotkeyRegistrationStatusProvider);
    // Read once — this step only needs the platform capability, not live
    // updates to it (mirrors `_PushToTalkRow` in `feedback_section.dart`).
    final supportsKeyUp = ref
        .read(hotkeyServiceProvider.notifier)
        .supportsKeyUp;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = L10n.of(context);

    final textPrimary = isDark
        ? WpColorsDark.textPrimary
        : WpColorsLight.textPrimary;
    final textSecondary = isDark
        ? WpColorsDark.textSecondary
        : WpColorsLight.textSecondary;
    final accentGradient = isDark
        ? WpColorsDark.accentWarmGradient
        : WpColorsLight.accentWarmGradient;
    final surfaceVariant =
        (isDark ? WpColorsDark.surfaceVariant : WpColorsLight.surfaceVariant)
            .withValues(alpha: 0.55);
    final borderColor = isDark
        ? WpColorsDark.borderSubtle
        : WpColorsLight.borderSubtle;

    final hotkeyKey = settings.hotkeyKey;
    final hotkeyDisplay = settings.hotkey.hotkeyKeyDisplay;
    final hotkeyModifiers = settings.hotkeyModifiers;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.onboardingTriggerTitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: WpTypography.headline,
            fontWeight: FontWeight.bold,
            color: textPrimary,
          ),
        ),
        const SizedBox(height: WpSpacing.sm),
        Text(
          l10n.onboardingTriggerSubtitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: WpTypography.subheading,
            color: textSecondary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: WpSpacing.xxl),

        // Confirmed conflict — resolve it here, before the test recording
        // exercises this hotkey. Non-blocking for Next (see ReadyStep's
        // residual gate); a user who skips this warning just meets it again
        // as a disabled Start button.
        if (status == HotkeyRegistrationStatus.conflict) ...[
          _HotkeyConflictWarnBox(
            key: kTriggerStepConflictWarnBoxKey,
            title: l10n.onboardingTriggerHotkeyConflictTitle,
            body: l10n.onboardingTriggerHotkeyConflictBody,
            isDark: isDark,
          ),
          const SizedBox(height: WpSpacing.md),
          HotkeyRecorderDialog(
            key: kTriggerStepInlineRecorderKey,
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
          const SizedBox(height: WpSpacing.lg),
        ],

        // Hotkey + push-to-talk settings card.
        Container(
          decoration: BoxDecoration(
            color: surfaceVariant,
            borderRadius: WpRadius.borderLg,
            border: Border.all(color: borderColor),
          ),
          padding: const EdgeInsets.symmetric(horizontal: WpSpacing.sm),
          child: Column(
            children: [
              SettingRow(
                icon: LucideIcons.keyboard,
                label: l10n.onboardingTriggerCurrentHotkey,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    HotkeyDisplay(
                      hotkeyKey: hotkeyKey,
                      hotkeyModifiers: hotkeyModifiers,
                      hotkeyKeyDisplay: hotkeyDisplay,
                    ),
                    const SizedBox(width: WpSpacing.sm),
                    OutlinedButton(
                      key: kTriggerStepChangeHotkeyKey,
                      onPressed: () async {
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
                      child: Text(l10n.settingsChangeHotkey),
                    ),
                  ],
                ),
              ),
              _PushToTalkRow(
                settings: settings,
                supportsKeyUp: supportsKeyUp,
                l10n: l10n,
              ),
            ],
          ),
        ),
        const SizedBox(height: WpSpacing.xxl),

        Row(
          children: [
            TextButton(
              onPressed: onBack,
              child: Text(
                l10n.onboardingBack,
                style: TextStyle(color: textSecondary),
              ),
            ),
            const Spacer(),
            SizedBox(
              width: 140,
              // loam-ignore: a11y-interactive-semantics – semantics provided in WpAccentButton.build
              child: WpAccentButton(
                key: kTriggerStepNextButtonKey,
                label: l10n.onboardingNext,
                gradient: accentGradient,
                onPressed: onNext,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Push-to-Talk toggle row (platform-aware) — mirrors
// `feedback_section.dart`'s `_PushToTalkRow` so Settings and onboarding never
// drift on wording or gating behavior.
// ---------------------------------------------------------------------------

class _PushToTalkRow extends ConsumerWidget {
  const _PushToTalkRow({
    required this.settings,
    required this.supportsKeyUp,
    required this.l10n,
  });

  static final _log = AppLogger('OnboardingTriggerPtt');

  final AppSettings settings;
  final bool supportsKeyUp;
  final L10n l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final toggle = Switch(
      key: kTriggerStepPttToggleKey,
      value: settings.pushToTalk,
      onChanged: supportsKeyUp
          ? (v) {
              ref
                  .read(settingsProvider.notifier)
                  .updateSettings((s) => s.copyWith(pushToTalk: v));
              try {
                ref.read(telemetryProvider).trackSettingChange('hotkey_mode');
              } catch (e) {
                _log.debug('telemetry failed: $e');
              }
            }
          : null, // null disables the switch
    );

    return SettingRow(
      icon: LucideIcons.hand,
      label: l10n.settingsHoldToRecord,
      semanticToggledValue: supportsKeyUp ? settings.pushToTalk : null,
      trailing: supportsKeyUp
          ? toggle
          : Tooltip(message: l10n.pushToTalkUnavailableTooltip, child: toggle),
    );
  }
}

// ---------------------------------------------------------------------------
// Hotkey conflict warn-box — red banner shown when a confirmed OS-level
// registration conflict is detected. Moved here from `ready_step.dart` along
// with the rest of the hotkey-configuration UI.
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
                    fontSize: WpTypography.body,
                    fontWeight: FontWeight.w700,
                    color: dangerColor,
                  ),
                ),
                const SizedBox(height: WpSpacing.xxs),
                Text(
                  body,
                  style: TextStyle(
                    fontSize: WpTypography.small,
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
