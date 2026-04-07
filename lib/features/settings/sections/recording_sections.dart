/// Audio & Recording Safety settings sections.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../services/audio_service.dart';
import '../../../widgets/section.dart';
import '../settings_widgets.dart';

/// Audio input settings: microphone, gain, push-to-talk.
class AudioSection extends ConsumerWidget {
  const AudioSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
    final devicesAsync = ref.watch(audioInputDevicesProvider);
    final devices = devicesAsync.value ?? ['Default'];

    // True when real input devices were enumerated beyond the default.
    final hasRealDevices = devices.length > 1;

    // Ensure current setting is in the list (prevents blank dropdown).
    final currentMic = settings.microphone;
    final effectiveDevices = devices.contains(currentMic)
        ? devices
        : [currentMic, ...devices];

    return WpSection(
      title: l10n.settingsAudio,
      subtitle: l10n.settingsAudioSubtitle,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          if (hasRealDevices)
            SettingRow(
              icon: LucideIcons.mic,
              label: l10n.settingsMicrophone,
              trailing: settingsDropdown(
                context: context,
                value: currentMic,
                items: effectiveDevices,
                labels: effectiveDevices.map((d) {
                  if (d == 'Default') return l10n.settingsMicSystemDefault;
                  return d; // Real device names need no translation.
                }).toList(),
                onChanged: (v) => ref
                    .read(settingsProvider.notifier)
                    .updateSettings((s) => s.copyWith(microphone: v!)),
              ),
            )
          else
            // No real devices enumerated — show non-interactive system default.
            SettingRow(
              icon: LucideIcons.mic,
              label: l10n.settingsMicrophone,
              subtitle: l10n.settingsMicSystemHint,
              trailing: Text(
                l10n.settingsMicSystemDefault,
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.secondary,
                ),
              ),
            ),
          SettingRow(
            icon: LucideIcons.gauge,
            label: l10n.settingsGain,
            trailing: settingsSlider(
              context: context,
              value: settings.inputGain,
              min: 0,
              max: 300,
              divisions: 60,
              valueLabel: '${settings.inputGain.round()}%',
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .updateSettings((s) => s.copyWith(inputGain: v)),
            ),
          ),
          SettingRow(
            icon: LucideIcons.hand,
            label: l10n.settingsHoldToRecord,
            trailing: settingsToggle(
              value: settings.pushToTalk,
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .updateSettings((s) => s.copyWith(pushToTalk: v)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Recording safety: dead mic timeout, silence stop, max duration, VAD.
class RecordingSafetySection extends ConsumerWidget {
  const RecordingSafetySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;

    return WpSection(
      title: l10n.settingsRecordingSafety,
      subtitle: l10n.settingsRecordingSafetySubtitle,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          SettingRow(
            icon: LucideIcons.shieldAlert,
            label: l10n.settingsDeadMicTimeout,
            trailing: settingsSlider(
              context: context,
              value: settings.deadMicTimeout,
              min: 0,
              max: 10,
              divisions: 10,
              valueLabel: fmtSeconds(context, settings.deadMicTimeout),
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .updateSettings((s) => s.copyWith(deadMicTimeout: v)),
            ),
          ),
          SettingRow(
            icon: LucideIcons.timerOff,
            label: l10n.settingsAutoStopSilence,
            trailing: settingsSlider(
              context: context,
              value: settings.autoStopSilence,
              min: 0,
              max: 10,
              divisions: 10,
              valueLabel: fmtSeconds(context, settings.autoStopSilence),
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .updateSettings((s) => s.copyWith(autoStopSilence: v)),
            ),
          ),
          SettingRow(
            icon: LucideIcons.timer,
            label: l10n.settingsMaxRecordDuration,
            subtitle: l10n.settingsMaxRecordDurationSubtitle,
            trailing: settingsSlider(
              context: context,
              value: settings.maxRecordDuration.toDouble(),
              min: 0,
              max: 600,
              divisions: 20,
              valueLabel: fmtDuration(context, settings.maxRecordDuration),
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .updateSettings(
                      (s) => s.copyWith(maxRecordDuration: v.round())),
            ),
          ),
          SettingRow(
            icon: LucideIcons.scissors,
            label: l10n.settingsTrimSilence,
            subtitle: l10n.settingsTrimSilenceSubtitle,
            trailing: settingsToggle(
              value: settings.trimSilence,
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .updateSettings((s) => s.copyWith(trimSilence: v)),
            ),
          ),
          SettingRow(
            icon: LucideIcons.audioLines,
            label: l10n.settingsVoiceActivityDetection,
            subtitle: l10n.settingsVoiceActivityDetectionSubtitle,
            trailing: settingsToggle(
              value: settings.useVAD,
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .updateSettings((s) => s.copyWith(useVAD: v)),
            ),
          ),
          if (settings.useVAD)
            SettingRow(
              icon: LucideIcons.slidersHorizontal,
              label: l10n.settingsVadSensitivity,
              subtitle: l10n.settingsVadSensitivitySubtitle,
              trailing: settingsSlider(
                context: context,
                value: settings.vadSensitivity,
                min: 0.0,
                max: 1.0,
                divisions: 10,
                valueLabel: '${(settings.vadSensitivity * 100).round()}%',
                onChanged: (v) => ref
                    .read(settingsProvider.notifier)
                    .updateSettings((s) => s.copyWith(vadSensitivity: v)),
              ),
            ),
        ],
      ),
    );
  }
}
