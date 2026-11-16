/// Audio & Recording Safety settings sections.
library;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/config/settings_sections.dart'
    show maxInputGainDb, minInputGainDb;
import '../../../services/audio/speech_leveler.dart' show dbToGain, gainToDb;
import '../../../services/audio_service.dart';
import '../../../services/media_pause/media_pause_providers.dart';
import '../../recording/clipping_state.dart';
import '../record_duration_steps.dart';
import '../settings_widgets.dart';
import '../widgets/wp_settings_group.dart';

/// Audio input settings: microphone, gain.
class AudioSection extends ConsumerStatefulWidget {
  const AudioSection({super.key});

  @override
  ConsumerState<AudioSection> createState() => _AudioSectionState();
}

class _AudioSectionState extends ConsumerState<AudioSection> {
  /// Manual input volume in dB while the slider is being dragged. Only the
  /// release writes it to settings (UIA-SET-13).
  double? _gainDraftDb;

  @override
  void initState() {
    super.initState();
    // The device list is cached for the app run; re-enumerate on every visit
    // so a microphone plugged in meanwhile is offered (the dock menu does the
    // same when it opens).
    Future.microtask(() {
      if (mounted) ref.invalidate(audioInputDevicesProvider);
    });
  }

  /// Manual input volume ("Eingangslautstärke"): left quieter, right louder,
  /// in 1 dB steps. Stored as the linear factor `input_gain`.
  Widget _gainRow(L10n l10n, AppSettings settings) {
    final storedDb = gainToDb(
      settings.audioInput.inputGain,
    ).clamp(minInputGainDb, maxInputGainDb).toDouble();
    final db = _gainDraftDb ?? storedDb;
    return WpSettingsRow(
      rowId: 'recording-gain',
      title: l10n.settingsGain,
      subtitle: l10n.settingsGainSubtitle,
      trailing: settingsSlider(
        context: context,
        value: db,
        min: minInputGainDb,
        max: maxInputGainDb,
        divisions: (maxInputGainDb - minInputGainDb).round(),
        valueLabel: inputGainLabel(db),
        onChanged: (v) => setState(() => _gainDraftDb = v),
        onChangeEnd: (v) {
          setState(() => _gainDraftDb = null);
          ref
              .read(settingsProvider.notifier)
              .updateSettings(
                (s) => s.copyWithSections(
                  audioInput: s.audioInput.copyWith(
                    inputGain: v.round() == 0 ? 1.0 : dbToGain(v),
                  ),
                ),
              );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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

    return WpSettingsGroup(
      heading: l10n.settingsAudio,
      children: [
        if (hasRealDevices)
          WpSettingsRow(
            rowId: 'recording-microphone',
            title: l10n.settingsMicrophone,
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
          // Once the lookup has finished, say why nothing is offered
          // (UIA-SET-07); while it runs, keep the neutral hint.
          WpSettingsRow(
            rowId: 'recording-microphone',
            title: l10n.settingsMicrophone,
            subtitle: devicesAsync.isLoading
                ? l10n.settingsMicSystemHint
                : ref.watch(inputDeviceToolMissingProvider)
                ? l10n.settingsMicToolMissingHint
                : l10n.settingsMicNoDeviceHint,
            trailing: Text(
              l10n.settingsMicSystemDefault,
              style: TextStyle(
                fontSize: WpTypography.body,
                color: Theme.of(context).colorScheme.secondary,
              ),
            ),
          ),
        // #1611: the automatic level is the default; the manual volume
        // only appears when it is off (like the hold threshold under its
        // mode), so the page stays calm for most users.
        WpSettingsRow(
          rowId: 'recording-auto-level',
          switchNamesRow: true,
          title: l10n.settingsAutoLevel,
          subtitle: l10n.settingsAutoLevelSubtitle,
          trailing: settingsToggle(
            label: l10n.settingsAutoLevel,
            key: const Key('autoLevelToggle'),
            testId: 'recording-auto-level-toggle',
            value: settings.audioInput.autoLevel,
            onChanged: (v) => ref
                .read(settingsProvider.notifier)
                .updateSettings(
                  (s) => s.copyWithSections(
                    audioInput: s.audioInput.copyWith(autoLevel: v),
                  ),
                ),
          ),
        ),
        if (!settings.audioInput.autoLevel) _gainRow(l10n, settings),
        _PauseMediaRow(settings: settings),
        // Only a child while the banner has something to show: the group puts
        // a divider before each child, and the banner renders nothing otherwise,
        // which left a stray rule at the bottom of the card.
        if (ref.watch(clippingStateProvider).shouldShowBanner)
          const _ClippingBanner(),
      ],
    );
  }
}

/// Text next to the volume slider: the change against unchanged in whole dB,
/// "0 dB" for unchanged. Signed so "louder" and "quieter" read at a glance.
String inputGainLabel(double db) {
  final rounded = db.round();
  if (rounded == 0) return '0 dB';
  return rounded > 0 ? '+$rounded dB' : '\u2212${-rounded} dB';
}

/// Opt-in switch: pause music/video while recording (#563). Shows "not
/// available" and stays off where the system gives no media control.
class _PauseMediaRow extends ConsumerWidget {
  const _PauseMediaRow({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final available = ref.watch(mediaPauseAvailableProvider).value ?? true;
    // macOS: Apple blocks media control for third-party apps since 15.4, so
    // the row is permanently unavailable there. A stored `true` stays saved
    // but has no effect (#1254).
    final unavailableText = defaultTargetPlatform == TargetPlatform.macOS
        ? l10n.settingsPauseMediaUnavailableMacos
        : l10n.settingsPauseMediaUnavailable;
    final on = available && settings.audioInput.pauseMediaWhileRecording;
    return WpSettingsRow(
      rowId: 'recording-pause-media',
      title: l10n.settingsPauseMedia,
      subtitle: available
          ? l10n.settingsPauseMediaSubtitle
          : '${l10n.settingsPauseMediaSubtitle}\n$unavailableText',
      switchNamesRow: available,
      trailing: settingsToggle(
        label: l10n.settingsPauseMedia,
        key: const Key('pauseMediaToggle'),
        testId: 'recording-pause-media-toggle',
        value: on,
        disabledReason: available ? null : unavailableText,
        onChanged: available
            ? (v) => ref
                  .read(settingsProvider.notifier)
                  .updateSettings(
                    (s) => s.copyWithSections(
                      audioInput: s.audioInput.copyWith(
                        pauseMediaWhileRecording: v,
                      ),
                    ),
                  )
            : null,
      ),
    );
  }
}

/// Subtle inline banner at the end of the audio card. Shown only when
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
    return SettingsRowFrame(
      rowId: 'recording-clipping-hint',
      child: settingsInlineNotice(
        context: context,
        message: l10n.settingsClippingBanner,
        onDismiss: () => ref.read(clippingStateProvider.notifier).dismiss(),
        dismissTooltip: l10n.settingsClippingDismiss,
        // Zero top: the banner sits flush beneath the gain slider it annotates.
        // The one geometry difference among the three notices that means
        // something, so it is the one the shared helper takes as a parameter.
        margin: const EdgeInsets.fromLTRB(
          WpSpacing.sm,
          0,
          WpSpacing.sm,
          WpSpacing.xs,
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

    return WpSettingsGroup(
      heading: l10n.settingsRecordingSafety,
      children: [
        WpSettingsRow(
          rowId: 'recording-dead-mic',
          title: l10n.settingsDeadMicTimeout,
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
        WpSettingsRow(
          rowId: 'recording-auto-stop-silence',
          title: l10n.settingsAutoStopSilence,
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
        WpSettingsRow(
          rowId: 'recording-max-duration',
          title: l10n.settingsMaxRecordDuration,
          subtitle: l10n.settingsMaxRecordDurationSubtitle,
          trailing: settingsSlider(
            context: context,
            value: recordDurationStepIndex(
              settings.maxRecordDuration,
            ).toDouble(),
            min: 0,
            max: (kRecordDurationStepCount - 1).toDouble(),
            divisions: kRecordDurationStepCount - 1,
            valueLabel: fmtDuration(
              context,
              recordDurationSecondsAt(
                recordDurationStepIndex(settings.maxRecordDuration),
              ),
            ),
            onChanged: (v) {
              final index = v.round();
              // Off-grid legacy values keep their stored number until the
              // user actually moves to a different step.
              if (index ==
                  recordDurationStepIndex(settings.maxRecordDuration)) {
                return;
              }
              ref
                  .read(settingsProvider.notifier)
                  .updateSettings(
                    (s) => s.copyWith(
                      maxRecordDuration: recordDurationSecondsAt(index),
                    ),
                  );
            },
          ),
        ),
      ],
    );
  }
}
