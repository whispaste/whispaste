/// Keyboard Shortcut & Sound Feedback settings sections.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/settings_enums.dart';
import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/hotkey_recorder.dart';
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
      child: SettingRow(
        icon: LucideIcons.keyboard,
        label: l10n.settingsCurrentHotkey,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            HotkeyDisplay(
              hotkeyKey: settings.hotkeyKey,
              hotkeyModifiers: settings.hotkeyModifiers,
            ),
            const SizedBox(width: WpSpacing.sm),
            OutlinedButton(
              onPressed: () async {
                final result = await HotkeyRecorderDialog.show(
                  context,
                  initialKey: settings.hotkeyKey,
                  initialModifiers: settings.hotkeyModifiers,
                );
                if (result != null) {
                  ref.read(settingsProvider.notifier).updateSettings(
                        (s) => s.copyWith(
                      hotkeyKey: result.key,
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
            icon: LucideIcons.volume2,
            label: l10n.settingsRecordStartSound,
            trailing: settingsToggle(
              value: settings.recordStartSound,
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .updateSettings((s) => s.copyWith(recordStartSound: v)),
            ),
          ),
          SettingRow(
            icon: LucideIcons.volumeX,
            label: l10n.settingsRecordStopSound,
            trailing: settingsToggle(
              value: settings.recordStopSound,
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .updateSettings((s) => s.copyWith(recordStopSound: v)),
            ),
          ),
          SettingRow(
            icon: LucideIcons.bellRing,
            label: l10n.settingsTranscriptionCompleteSound,
            trailing: settingsToggle(
              value: settings.transcriptionCompleteSound,
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .updateSettings(
                      (s) => s.copyWith(transcriptionCompleteSound: v)),
            ),
          ),
          SettingRow(
            icon: LucideIcons.alarmClock,
            label: l10n.settingsDurationWarningSound,
            trailing: settingsToggle(
              value: settings.durationWarningSound,
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .updateSettings(
                      (s) => s.copyWith(durationWarningSound: v)),
            ),
          ),
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
      child: SettingRow(
        icon: LucideIcons.clipboardCheck,
        label: l10n.settingsAfterTranscription,
        subtitle: l10n.settingsAfterTranscriptionSubtitle,
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
                .updateSettings(
                    (s) => s.copyWith(afterTranscription: v));
          },
        ),
      ),
    );
  }
}
