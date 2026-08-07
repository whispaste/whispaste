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
import '../../../widgets/wp_button.dart';
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

/// Content of the Hotkey onboarding page: the global hotkey, and whether it's
/// held (push-to-talk) or pressed-to-toggle.
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
/// navigation (Back/Next) and the page heading are owned by the onboarding
/// shell.
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

    final textSecondary = isDark
        ? WpColorsDark.textSecondary
        : WpColorsLight.textSecondary;

    final hotkeyKey = settings.hotkeyKey;
    final hotkeyDisplay = settings.hotkey.hotkeyKeyDisplay;
    final hotkeyModifiers = settings.hotkeyModifiers;

    // Content only, no title: the Hotkey page owns the heading (see the
    // overlay's page composition), which is the same string this block used
    // to carry as a section label. The settings-style row treatment below is
    // kept from the merged page — it reads as one row of the same kind the
    // rest of the flow uses, not as a hero.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Confirmed conflict — resolve it here, before the test recording
        // exercises this hotkey. Non-blocking for Next (see ReadyStep's
        // residual gate); a user who skips this warning just meets it again
        // as a disabled Start button.
        //
        // This branch adds the warn box plus a full inline
        // HotkeyRecorderDialog. On the merged Model & Hotkey page that meant
        // 914 px (de) / 921 px (he) against a 551-px viewport — ~370 px of
        // forced scrolling, documented as out of reach without a flow change.
        // The flow change happened: the hotkey block has its own page now, and
        // the branch fits without scrolling (534 px in German and in Hebrew —
        // measured, see the fixed-window group in
        // `onboarding_overlay_test.dart`). The last ~40 px come from three
        // deliberate compressions, so re-measure both locales before spending
        // them: the page heading drops its subtitle while a conflict is up
        // (see the overlay), the gaps below are one step tighter than the
        // page's usual rhythm, and the German conflict body is worded to stay
        // on one line. The trailing "Ändern" button below is `dense` for the
        // same reason as the compressions above, not just for the 17 px of
        // slack it buys back — see its own comment.
        if (status == HotkeyRegistrationStatus.conflict) ...[
          _HotkeyConflictWarnBox(
            key: kTriggerStepConflictWarnBoxKey,
            title: l10n.onboardingTriggerHotkeyConflictTitle,
            body: l10n.onboardingTriggerHotkeyConflictBody,
            isDark: isDark,
          ),
          const SizedBox(height: WpSpacing.xs),
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
          const SizedBox(height: WpSpacing.sm),
        ],

        // Hotkey row — settings-style (Conductor pattern): label on the
        // leading side, the key caps + change button trailing. The key-cap
        // rendering of HotkeyDisplay keeps the hotkey visually prominent
        // without the tall centered hero treatment. Frameless like every
        // other onboarding settings row: the filled, outlined card around it
        // was one of four competing boxes on this page, and dropping it also
        // returns 10 px (2 px border + 2x4 px padding) to the page's very
        // tight height budget.
        Padding(
          padding: const EdgeInsetsDirectional.only(start: kSettingRowInset),
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
              // dense: this row's label already runs at WpTypography.small —
              // a standard (48px) button would out-shout the row it answers
              // to. See wp_button.dart's dense doc: "trailing slot of a
              // dense settings row", exactly this slot.
              WpButton(
                key: kTriggerStepChangeHotkeyKey,
                label: l10n.settingsChangeHotkey,
                variant: WpButtonVariant.secondary,
                size: WpButtonSize.dense,
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
              ),
            ],
          ),
        ),
        const SizedBox(height: WpSpacing.sm),

        // Mode row — hold vs. toggle. The switch stays the single control;
        // the row's subtitle re-words itself to describe the currently
        // selected behavior, so flipping the switch gives immediate,
        // plain-language feedback on what the hotkey will now do.
        Padding(
          padding: const EdgeInsetsDirectional.only(start: kSettingRowInset),
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
    final toggle = settingsToggle(
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
      // Vertically tighter than the horizontal inset on purpose: this box
      // shares the page's tightest branch with a full inline recorder, and
      // the 8 px it gives back are what keeps that branch off the scroll bar
      // (see the fixed-window group in `onboarding_overlay_test.dart`).
      padding: const EdgeInsets.symmetric(
        horizontal: WpSpacing.md,
        vertical: WpSpacing.xs,
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
