/// Audio & Recording Safety settings sections.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/audio_service.dart';
import '../../recording/clipping_state.dart';
import '../../../widgets/section.dart';
import '../settings_widgets.dart';

/// Audio input settings: microphone, gain.
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
              // The slider value is the gain expressed as a percentage
              // (0–300 %). The stored field is the raw multiplier (0.0–3.0).
              value: settings.audioInput.inputGain * 100.0,
              min: 0,
              max: 300,
              divisions: 60,
              valueLabel: '${(settings.audioInput.inputGain * 100).round()}%',
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .updateSettings((s) => s.copyWith(inputGain: v / 100.0)),
            ),
          ),
          const _ClippingBanner(),
        ],
      ),
    );
  }
}

/// Subtle inline banner directly beneath the gain slider. Shown only when
/// the last successful recording produced one or more clipped int16 samples
/// (see [clippingStateProvider]).
///
/// No modal alert, no sound, no OS notification — just a warning icon plus
/// a localized message and a dismiss control that resets the underlying
/// counter to `0`.
class _ClippingBanner extends ConsumerWidget {
  const _ClippingBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clipping = ref.watch(clippingStateProvider);
    if (!clipping.shouldShowBanner) return const SizedBox.shrink();

    final l10n = L10n.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final warnColor = isDark ? WpColorsDark.warning : WpColorsLight.warning;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WpSpacing.sm,
        0,
        WpSpacing.sm,
        WpSpacing.xs,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: WpSpacing.sm,
          vertical: WpSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: warnColor.withValues(alpha: 0.12),
          borderRadius: WpRadius.borderMd,
          border: Border.all(color: warnColor.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.alertTriangle, size: 16, color: warnColor),
            const SizedBox(width: WpSpacing.xs),
            Expanded(
              child: Text(
                l10n.settingsClippingBanner,
                style: TextStyle(fontSize: 12, color: warnColor),
              ),
            ),
            const SizedBox(width: WpSpacing.xs),
            IconButton(
              icon: Icon(LucideIcons.x, size: 16, color: warnColor),
              tooltip: l10n.settingsClippingDismiss,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              splashRadius: 14,
              onPressed: () =>
                  ref.read(clippingStateProvider.notifier).dismiss(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Recording safety: dead mic timeout, silence stop, max duration.
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
                    (s) => s.copyWith(maxRecordDuration: v.round()),
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
