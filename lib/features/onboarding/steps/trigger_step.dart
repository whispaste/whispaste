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

/// Hotkey configuration content of the Model & Hotkey onboarding page: the
/// global hotkey, and whether it's held (push-to-talk) or pressed-to-toggle.
///
/// Sits on the page before the guided test recording so that test exercises
/// the real, just-configured hotkey and mode — not a stale default the user
/// hasn't seen yet.
///
/// Both settings have valid defaults (`Ctrl/Cmd+Shift+D`, toggle mode), so
/// advancing without changing anything is a legitimate choice, not a partial
/// state. The one exception is a confirmed hotkey conflict: the final
/// onboarding page keeps a residual gate on its completion CTA for the case
/// where the user moves past an unresolved conflict here. Content only —
/// navigation (Back/Next) is owned by the onboarding shell.
class TriggerStep extends ConsumerWidget {
  const TriggerStep({super.key});

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
    final surfaceVariant =
        (isDark ? WpColorsDark.surfaceVariant : WpColorsLight.surfaceVariant)
            .withValues(alpha: 0.55);
    final borderColor = isDark
        ? WpColorsDark.borderSubtle
        : WpColorsLight.borderSubtle;

    final hotkeyKey = settings.hotkeyKey;
    final hotkeyDisplay = settings.hotkey.hotkeyKeyDisplay;
    final hotkeyModifiers = settings.hotkeyModifiers;

    // Deliberately denser than pages 1/2: this page bundles two former
    // steps plus the appearance block, so the per-block headers shrink to
    // compact leading labels (heading-size title, small subtitle) and the
    // hotkey presentation becomes a single settings-style row — same
    // elements, same keys, same handlers, just tighter geometry so the whole
    // page fits the fixed 1100×720 onboarding window without scrolling.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.onboardingTriggerTitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: WpTypography.subheading,
            fontWeight: FontWeight.bold,
            color: textPrimary,
          ),
        ),
        const SizedBox(height: WpSpacing.xxs),
        Text(
          l10n.onboardingTriggerSubtitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: WpTypography.small,
            color: textSecondary,
            height: 1.3,
          ),
        ),
        const SizedBox(height: WpSpacing.xs),

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

        // Hotkey card — settings-style row (Conductor pattern): label on the
        // leading side, the key caps + change button trailing. The key-cap
        // rendering of HotkeyDisplay keeps the hotkey visually prominent
        // without the tall centered hero treatment.
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: surfaceVariant,
            borderRadius: WpRadius.borderLg,
            border: Border.all(color: borderColor),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: WpSpacing.md,
            vertical: WpSpacing.xxs,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.onboardingTriggerCurrentHotkey,
                  style: TextStyle(
                    fontSize: WpTypography.small,
                    fontWeight: FontWeight.w600,
                    color: textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: WpSpacing.md),
              HotkeyDisplay(
                hotkeyKey: hotkeyKey,
                hotkeyModifiers: hotkeyModifiers,
                hotkeyKeyDisplay: hotkeyDisplay,
              ),
              const SizedBox(width: WpSpacing.md),
              OutlinedButton(
                key: kTriggerStepChangeHotkeyKey,
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(horizontal: WpSpacing.sm),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
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
        const SizedBox(height: WpSpacing.xs),

        // Mode card — hold vs. toggle. The switch stays the single control;
        // the row's subtitle re-words itself to describe the currently
        // selected behavior, so flipping the switch gives immediate,
        // plain-language feedback on what the hotkey will now do.
        Container(
          decoration: BoxDecoration(
            color: surfaceVariant,
            borderRadius: WpRadius.borderLg,
            border: Border.all(color: borderColor),
          ),
          padding: const EdgeInsets.symmetric(horizontal: WpSpacing.sm),
          child: _PushToTalkRow(
            settings: settings,
            supportsKeyUp: supportsKeyUp,
            l10n: l10n,
          ),
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

    // Subtitle mirrors the live value: it always describes what pressing the
    // hotkey will do *right now*, so the toggle's effect is never abstract.
    final modeHint = settings.pushToTalk && supportsKeyUp
        ? l10n.onboardingTriggerModeHoldHint
        : l10n.onboardingTriggerModeToggleHint;

    // Same content and semantics as the SettingRow this used to be, in a
    // denser custom row (no min-touch-target box, no extra vertical padding)
    // so the merged page fits the fixed onboarding window without scrolling.
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textMuted = isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;

    return Semantics(
      label: l10n.settingsHoldToRecord,
      hint: modeHint,
      toggled: supportsKeyUp ? settings.pushToTalk : null,
      child: Row(
        children: [
          Icon(
            LucideIcons.hand,
            size: WpIconSize.sm,
            color: Theme.of(context).colorScheme.secondary,
          ),
          const SizedBox(width: WpSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.settingsHoldToRecord,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                Padding(
                  // 2px title-subtitle gap: tighter than WpSpacing.xxs so
                  // the pair reads as one unit (mirrors SettingRow).
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    modeHint,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: textMuted),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: WpSpacing.sm),
          if (supportsKeyUp)
            toggle
          else
            Tooltip(message: l10n.pushToTalkUnavailableTooltip, child: toggle),
        ],
      ),
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
