import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'overview_providers.dart' show overviewSpeechSetupProvider;

import '../../core/config/selectable_speech_models.dart' show SpeechModelEngine;
import '../../core/config/settings_enums.dart' show SttProviderType;
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/overview/speech_setup.dart';
import '../../core/overview/storage_usage.dart' show formatStorageBytes;
import '../../core/recording/recording_helpers.dart' show displayNameForModel;
import '../../core/recording/recording_state.dart'
    show isDictationBusy, recordingPhaseProvider;
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../services/audio_service.dart' show audioInputDevicesProvider;
import '../../services/system_usage_service.dart';
import '../../widgets/wp_banner.dart';
import '../../widgets/wp_card.dart';
import '../../widgets/wp_label_value_row.dart';

/// "System": the engine, speech model and microphone a dictation uses
/// (#1567), then the load of the whole machine, memory in use and the free
/// space on the WhisPaste data volume. Off by default; switched on under
/// "Übersicht anpassen". The load figures are read only while this card is on
/// the page, the window is active, and it is switched on. The speech rows
/// follow the states the dock and Settings already keep
/// ([overviewSpeechSetupProvider]); only the microphone list is read again,
/// once when the card appears and when the window becomes active, never while
/// a dictation runs.
///
/// Warnings for little free memory and a nearly full volume appear in the card
/// only. The status line needs the same reading to warn, and that reading runs
/// only while this card is on, so the status line would have nothing to show
/// otherwise.
class OverviewSystemCard extends ConsumerStatefulWidget {
  const OverviewSystemCard({super.key});

  @override
  ConsumerState<OverviewSystemCard> createState() => _OverviewSystemCardState();
}

class _OverviewSystemCardState extends ConsumerState<OverviewSystemCard>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The first reading waits until the first frame and the window state is
    // known. A window that starts hidden does not poll at all.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = WidgetsBinding.instance.lifecycleState;
      final active = state == null || state == AppLifecycleState.resumed;
      _setActive(active);
      if (active) _refreshMicrophones();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Hidden, paused or unfocused window: nothing is read until it is active.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final active = state == AppLifecycleState.resumed;
    if (active && !_active) _refreshMicrophones();
    _setActive(active);
  }

  bool _active = false;

  void _setActive(bool active) {
    _active = active;
    ref.read(systemUsageProvider.notifier).setActive(active: active);
  }

  /// Lists the input devices again, so a microphone plugged in since the
  /// last listing is not shown as missing. Skipped while a dictation runs:
  /// its start lists the devices itself and must not meet a second listing.
  void _refreshMicrophones() {
    if (isDictationBusy(ref.read(recordingPhaseProvider))) return;
    ref.invalidate(audioInputDevicesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final s = ref.watch(systemUsageProvider);
    final speech = ref.watch(overviewSpeechSetupProvider);

    String cpuValue() {
      if (!s.loaded) return '…';
      if (s.cpuReadable != true) return l10n.overviewSystemUnavailable;
      final percent = s.cpuPercent;
      return percent == null
          ? '…'
          : l10n.overviewSystemPercent(percent.round());
    }

    String ramValue() {
      if (!s.loaded) return '…';
      final total = s.ramTotalMB;
      final available = s.ramAvailableMB;
      if (total == null || available == null) {
        return l10n.overviewSystemUnavailable;
      }
      const mb = 1024 * 1024;
      final used = (total - available).clamp(0, total);
      return l10n.overviewSystemRamValue(
        formatStorageBytes(used * mb, lang),
        formatStorageBytes(total * mb, lang),
      );
    }

    String diskValue() {
      if (!s.loaded) return '…';
      final free = s.diskFreeBytes;
      return free == null
          ? l10n.overviewSystemUnavailable
          : formatStorageBytes(free, lang);
    }

    Widget row(String id, String label, String value) => WpLabelValueRow(
      key: ValueKey('overview-system-$id'),
      label: label,
      value: value,
      valueKey: ValueKey('overview-system-$id-value'),
    );

    return WpCard(
      key: const ValueKey('overview-system'),
      title: l10n.overviewSystemTitle,
      titleTestId: 'overview-system-title',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          row(
            'engine',
            l10n.settingsSpeechRecognition,
            overviewEngineText(speech, l10n),
          ),
          const SizedBox(height: WpSpacing.xs),
          row('model', l10n.settingsSttEngine, overviewModelText(speech, l10n)),
          const SizedBox(height: WpSpacing.xs),
          row('mic', l10n.settingsMicrophone, overviewMicText(speech, l10n)),
          const SizedBox(height: WpSpacing.md),
          row('cpu', l10n.overviewSystemCpu, cpuValue()),
          const SizedBox(height: WpSpacing.xs),
          row('ram', l10n.overviewSystemRam, ramValue()),
          const SizedBox(height: WpSpacing.xs),
          row('disk', l10n.overviewSystemDisk, diskValue()),
          if (s.ramLow) ...[
            const SizedBox(height: WpSpacing.md),
            _Warning(
              testId: 'overview-system-warning-ram',
              text: l10n.overviewSystemRamLow,
            ),
          ],
          if (s.diskLow) ...[
            const SizedBox(height: WpSpacing.md),
            _Warning(
              testId: 'overview-system-warning-disk',
              text: l10n.overviewSystemDiskLow,
            ),
          ],
          const SizedBox(height: WpSpacing.md),
          Text(
            key: const ValueKey('overview-system-note'),
            l10n.overviewSystemNote,
            style: WpTextStyles.rowNote,
          ),
        ],
      ),
    );
  }
}

/// The engine row: its name and where it runs.
String overviewEngineText(OverviewSpeechSetup s, L10n l10n) {
  final name = switch (s.engine) {
    SpeechModelEngine.whisper => l10n.settingsSttEngineWhisper,
    SpeechModelEngine.parakeet => l10n.settingsSttEngineParakeet,
    SpeechModelEngine.system => l10n.settingsSttEngineSystem,
    SpeechModelEngine.openAI => SttProviderType.openAI.value,
    SpeechModelEngine.deepgram => SttProviderType.deepgram.value,
    SpeechModelEngine.customEndpoint => l10n.settingsSttCustomEndpoint,
  };
  return s.onDevice
      ? l10n.overviewSystemEngineOnDevice(name)
      : l10n.overviewSystemEngineCloud(name);
}

/// The speech-model row: the model's display name and, on the device, its
/// state. A missing value is said, never left empty.
String overviewModelText(OverviewSpeechSetup s, L10n l10n) {
  if (s.modelId.isEmpty) return l10n.overviewSystemModelNotSet;
  final name = s.onDevice ? displayNameForModel(s.modelId, l10n) : s.modelId;
  final state = switch (s.modelState) {
    OverviewModelState.ready => l10n.overviewSystemModelReady,
    OverviewModelState.loading => l10n.dockMenuModelLoading,
    OverviewModelState.loadsOnDictation =>
      l10n.overviewSystemModelLoadsOnDictation,
    OverviewModelState.notDownloaded => l10n.overviewSystemModelNotDownloaded,
    OverviewModelState.downloading => l10n.overviewSystemModelDownloading(
      s.downloadPercent ?? 0,
    ),
    OverviewModelState.failed => l10n.overviewSystemModelFailed,
    OverviewModelState.unavailable => l10n.overviewSystemModelUnavailable,
    OverviewModelState.cloud => null,
  };
  return state == null ? name : '$name · $state';
}

/// The microphone row.
String overviewMicText(OverviewSpeechSetup s, L10n l10n) =>
    switch (s.micState) {
      OverviewMicState.systemDefault => l10n.settingsMicSystemDefault,
      OverviewMicState.device => s.micName ?? l10n.settingsMicSystemDefault,
      OverviewMicState.disconnected => l10n.overviewSystemMicDisconnected(
        s.micName ?? '',
      ),
      OverviewMicState.noneFound => l10n.overviewSystemMicNoneFound,
      OverviewMicState.noAccess => l10n.overviewSystemMicNoAccess,
    };

/// A warning in the card, announced once when it appears.
class _Warning extends StatelessWidget {
  const _Warning({required this.testId, required this.text});

  final String testId;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: ValueKey(testId),
      liveRegion: true,
      container: true,
      child: WpBannerSurface(
        tone: WpBannerTone.warning,
        child: Text(text, style: WpTextStyles.rowNote),
      ),
    );
  }
}
