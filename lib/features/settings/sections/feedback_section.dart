/// Keyboard Shortcut & Sound Feedback settings sections.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/settings_enums.dart';
import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/hotkey_service.dart';
import '../../../services/sound_feedback_service.dart';
import '../../../widgets/hotkey_recorder.dart';
import '../../../widgets/paste_capability_indicator.dart';
import '../../../widgets/section.dart';
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
            trailing: Switch(
              value: settings.hotkeyEnabled,
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .updateSettings((s) => s.copyWith(hotkeyEnabled: v)),
            ),
          ),
          AnimatedOpacity(
            opacity: settings.hotkeyEnabled ? 1.0 : 0.4,
            duration: const Duration(milliseconds: 200),
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
                    OutlinedButton(
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
                      child: Text(l10n.settingsChangeHotkey),
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

  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);

    // Read the notifier directly — we only need supportsKeyUp once per build
    // and do not need to rebuild on hotkey-service state changes.
    final supportsKeyUp = ref
        .read(hotkeyServiceProvider.notifier)
        .supportsKeyUp;

    final toggle = Switch(
      value: settings.pushToTalk,
      onChanged: supportsKeyUp
          ? (v) => ref
                .read(settingsProvider.notifier)
                .updateSettings((s) => s.copyWith(pushToTalk: v))
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

    // Master state: ON iff at least one of the four sound fields is true.
    final masterOn =
        settings.sound.recordStartSound ||
        settings.sound.recordStopSound ||
        settings.sound.transcriptionCompleteSound ||
        settings.sound.durationWarningSound;

    void onMasterChanged(bool v) {
      ref
          .read(settingsProvider.notifier)
          .updateSettings(
            (s) => s.copyWith(
              recordStartSound: v,
              recordStopSound: v,
              transcriptionCompleteSound: v,
              durationWarningSound: v,
            ),
          );
    }

    return WpSection(
      title: l10n.settingsSoundFeedback,
      subtitle: l10n.settingsSoundFeedbackSubtitle,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          SettingRow(
            icon: LucideIcons.volume2,
            label: l10n.settingsSoundsEnabled,
            trailing: Semantics(
              label: l10n.settingsSoundsEnabled,
              toggled: masterOn,
              child: settingsToggle(
                value: masterOn,
                onChanged: onMasterChanged,
              ),
            ),
          ),
          if (masterOn)
            SettingRow(
              icon: LucideIcons.volume1,
              label: l10n.settingsSoundVolume,
              trailing: settingsSlider(
                context: context,
                value: settings.soundVolume,
                min: 0,
                max: 100,
                divisions: 20,
                valueLabel: '${settings.soundVolume.round()}%',
                onChanged: (v) => ref
                    .read(settingsProvider.notifier)
                    .updateSettings((s) => s.copyWith(soundVolume: v)),
                onChangeEnd: (v) => ref
                    .read(soundFeedbackProvider.notifier)
                    .playVolumePreview(v),
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
  const AfterTranscriptionSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;

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
              value: settings.afterTranscription,
              items: AfterTranscriptionAction.values
                  .map((e) => e.value)
                  .toList(),
              labels: [
                l10n.settingsAfterTranscriptionClipboard,
                l10n.settingsAfterTranscriptionPaste,
                l10n.settingsAfterTranscriptionBoth,
                l10n.settingsAfterTranscriptionNothing,
              ],
              onChanged: (v) {
                if (v == null) return;
                ref
                    .read(settingsProvider.notifier)
                    .updateSettings((s) => s.copyWith(afterTranscription: v));
              },
            ),
          ),
          if (settings.afterTranscriptionAction ==
                  AfterTranscriptionAction.paste ||
              settings.afterTranscriptionAction ==
                  AfterTranscriptionAction.clipboardAndPaste)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: PasteCapabilityIndicator(),
            ),
        ],
      ),
    );
  }
}
