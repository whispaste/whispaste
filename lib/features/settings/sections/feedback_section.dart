/// Keyboard Shortcut & Sound Feedback settings sections.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/build_config.dart';
import '../../../core/config/settings_enums.dart';
import '../../../core/config/settings_labels.dart';
import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/hotkey_service.dart';
import '../../../services/paste/paste_capability_notifier.dart';
import '../../../services/paste/paste_policy.dart';
import '../../../services/paste/paster.dart';
import '../../../services/sound_feedback_service.dart';
import '../../../services/telemetry_service.dart';
import '../../../widgets/hotkey_recorder.dart';
import '../../../widgets/paste_capability_indicator.dart';
import '../../../widgets/section.dart';
import '../../../widgets/wp_button.dart';
import '../settings_widgets.dart';

// ---------------------------------------------------------------------------
// Keyboard Shortcut section
// ---------------------------------------------------------------------------

class KeyboardShortcutSection extends ConsumerWidget {
  const KeyboardShortcutSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;

    return WpSection(
      title: l10n.settingsKeyboardShortcut,
      subtitle: l10n.settingsKeyboardShortcutSubtitle,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          SettingRow(
            icon: LucideIcons.toggleRight,
            label: l10n.settingsHotkeyEnabled,
            semanticToggledValue: settings.hotkeyEnabled,
            trailing: settingsToggle(
              value: settings.hotkeyEnabled,
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .updateSettings((s) => s.copyWith(hotkeyEnabled: v)),
            ),
          ),
          AnimatedOpacity(
            opacity: settings.hotkeyEnabled ? 1.0 : 0.4,
            duration: WpMotion.durationFor(context, WpMotion.normal),
            child: IgnorePointer(
              ignoring: !settings.hotkeyEnabled,
              child: SettingRow(
                icon: LucideIcons.keyboard,
                label: l10n.settingsCurrentHotkey,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    HotkeyDisplay(
                      hotkeyKey: settings.hotkeyKey,
                      hotkeyModifiers: settings.hotkeyModifiers,
                      hotkeyKeyDisplay: settings.hotkey.hotkeyKeyDisplay,
                    ),
                    const SizedBox(width: WpSpacing.sm),
                    WpButton(
                      label: l10n.settingsChangeHotkey,
                      variant: WpButtonVariant.secondary,
                      onPressed: () async {
                        final result = await HotkeyRecorderDialog.show(
                          context,
                          initialKey: settings.hotkeyKey,
                          initialDisplayKey: settings.hotkey.hotkeyKeyDisplay,
                          initialModifiers: settings.hotkeyModifiers,
                        );
                        if (result != null) {
                          ref
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
            ),
          ),
          _PushToTalkRow(settings: settings),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Push-to-Talk toggle row (platform-aware)
// ---------------------------------------------------------------------------

/// Renders the Hold-to-Record (Push-to-Talk) toggle.
///
/// When the current platform does not support key-up events
/// ([HotkeyService.supportsKeyUp] is false), the toggle is disabled
/// and wrapped in a [Tooltip] explaining the limitation.
class _PushToTalkRow extends ConsumerWidget {
  const _PushToTalkRow({required this.settings});

  static final _log = AppLogger('PushToTalkRow');

  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);

    // Read the notifier directly — we only need supportsKeyUp once per build
    // and do not need to rebuild on hotkey-service state changes.
    final supportsKeyUp = ref
        .read(hotkeyServiceProvider.notifier)
        .supportsKeyUp;

    final toggle = settingsToggle(
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
      trailing: supportsKeyUp
          ? toggle
          : Tooltip(message: l10n.pushToTalkUnavailableTooltip, child: toggle),
    );
  }
}

// ---------------------------------------------------------------------------
// Sound & Feedback section
// ---------------------------------------------------------------------------

class SoundFeedbackSection extends ConsumerWidget {
  const SoundFeedbackSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;

    return WpSection(
      title: l10n.settingsSoundFeedback,
      subtitle: l10n.settingsSoundFeedbackSubtitle,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          SettingRow(
            icon: LucideIcons.volume1,
            label: l10n.settingsSoundVolume,
            trailing: settingsSlider(
              context: context,
              value: settings.soundVolume,
              min: 0,
              max: 100,
              divisions: 20,
              valueLabel: settings.soundVolume == 0
                  ? l10n.settingsOff
                  : '${settings.soundVolume.round()}%',
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .updateSettings((s) => s.copyWith(soundVolume: v)),
              onChangeEnd: (v) =>
                  ref.read(soundFeedbackProvider.notifier).playVolumePreview(v),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// After Transcription section
// ---------------------------------------------------------------------------

class AfterTranscriptionSection extends ConsumerWidget {
  const AfterTranscriptionSection({
    super.key,
    this.autoPasteSupported = kAutoPasteSupported,
  });

  /// Overridable for tests; defaults to the real build-time flag ([kAutoPasteSupported]).
  final bool autoPasteSupported;

  static final _log = AppLogger('AfterTranscriptionSection');

  static String _labelFor(AfterTranscriptionAction action, L10n l10n) =>
      afterTranscriptionSettingsLabel(action, l10n);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;

    // Auto-paste-requiring actions don't exist as a selectable option at all
    // when the build can't perform them (MAS sandbox) — greying them out
    // with a tooltip would look like a bug to users who don't know they're
    // running a store build. The current value is routed through the same
    // resolver the recording pipeline uses, so a stale/synced "paste"
    // preference displays (and behaves) as "clipboard" instead of pointing
    // at an option that no longer exists in the list.
    final visibleActions = autoPasteSupported
        ? AfterTranscriptionAction.values
        : AfterTranscriptionAction.values
              .where(
                (a) =>
                    a != AfterTranscriptionAction.paste &&
                    a != AfterTranscriptionAction.clipboardAndPaste,
              )
              .toList();
    final resolvedAction = resolveAfterTranscriptionAction(
      settings.afterTranscriptionAction,
      autoPasteSupported: autoPasteSupported,
    );

    return WpSection(
      title: l10n.settingsAfterTranscription,
      subtitle: l10n.settingsAfterTranscriptionSubtitle,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          SettingRow(
            icon: LucideIcons.clipboardCheck,
            label: l10n.settingsAfterTranscriptionActionLabel,
            trailing: settingsDropdown(
              context: context,
              value: resolvedAction.value,
              items: visibleActions.map((e) => e.value).toList(),
              labels: visibleActions.map((e) => _labelFor(e, l10n)).toList(),
              onChanged: (v) {
                if (v == null) return;
                final newAction = AfterTranscriptionAction.values.firstWhere(
                  (a) => a.value == v,
                );
                ref
                    .read(settingsProvider.notifier)
                    .updateSettings((s) => s.copyWith(afterTranscription: v));
                try {
                  ref.read(telemetryProvider).trackSettingChange('auto_paste');
                } catch (e) {
                  _log.debug('telemetry failed: $e');
                }
                // The user just switched TO an Auto-Paste-requiring option —
                // request the OS permission right now instead of leaving them
                // to notice and tap the indicator's own "Grant" button below.
                // Skipped when already ready so re-selecting the same option
                // doesn't re-trigger the deep-link to System Settings.
                final requiresPaste =
                    newAction == AfterTranscriptionAction.paste ||
                    newAction == AfterTranscriptionAction.clipboardAndPaste;
                final alreadyReady =
                    ref
                        .read(pasteCapabilityNotifierProvider)
                        .capability
                        ?.status ==
                    PasteCapabilityStatus.ready;
                if (requiresPaste && Platform.isMacOS && !alreadyReady) {
                  unawaited(
                    ref
                        .read(pasteCapabilityNotifierProvider.notifier)
                        .requestGrant(),
                  );
                }
              },
            ),
          ),
          if (resolvedAction == AfterTranscriptionAction.paste ||
              resolvedAction == AfterTranscriptionAction.clipboardAndPaste)
            const Padding(
              padding: EdgeInsets.fromLTRB(
                WpSpacing.md,
                WpSpacing.sm,
                WpSpacing.md,
                WpSpacing.xs,
              ),
              child: PasteCapabilityIndicator(),
            ),
        ],
      ),
    );
  }
}
