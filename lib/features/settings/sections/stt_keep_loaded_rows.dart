/// "Keep model loaded" rows of the speech section (`stt.idleTimeoutMinutes`).
///
/// Automatic (`kSttIdleAutomatic`) decides from the machine's memory, 0 keeps
/// the Whisper model loaded, any other value unloads it after that many idle
/// minutes. Parakeet has no idle unload yet, so the rows are shown
/// for Whisper only: a row without an effect would be a silent no-op. The
/// slider keeps its drag position locally and stores the value when the drag
/// ends, so a drag does not rewrite the settings once per tick.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/config/settings_enums.dart';
import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../services/hardware_info_service.dart' as hw;
import '../../../services/stt/idle_unload_policy.dart' show kSttIdleAutomatic;
import '../settings_widgets.dart';
import '../widgets/wp_settings_group.dart';

/// Shortest and longest idle delay the slider offers, in minutes.
const int kSttIdleMinutesMin = 1;
const int kSttIdleMinutesMax = 120;

/// Delay used when "after idle" is chosen and no delay was stored before.
/// Matches the historical default, so the change is only a new choice.
const int kSttIdleMinutesDefault = 5;

class SttKeepLoadedRows extends ConsumerStatefulWidget {
  const SttKeepLoadedRows({super.key});

  @override
  ConsumerState<SttKeepLoadedRows> createState() => _SttKeepLoadedRowsState();
}

class _SttKeepLoadedRowsState extends ConsumerState<SttKeepLoadedRows> {
  /// Slider position while a drag runs; null otherwise.
  int? _dragMinutes;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
    if (settings.onDeviceEngine != OnDeviceEngine.whisper) {
      return const SizedBox.shrink();
    }
    final l10n = L10n.of(context);
    final minutes = settings.stt.idleTimeoutMinutes;
    final mode = minutes == kSttIdleAutomatic
        ? 'automatic'
        : (minutes == 0 ? 'always' : 'after');
    final shownMinutes = (_dragMinutes ?? minutes).clamp(
      kSttIdleMinutesMin,
      kSttIdleMinutesMax,
    );

    final modelMb = hw.sttModelVramMB[settings.effectiveModelId];
    final memory = modelMb == null
        ? null
        : l10n.settingsSttKeepLoadedMemory(
            '${NumberFormat('#,##0.#', l10n.localeName).format(modelMb / 1024)} GB',
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WpSettingsRow(
          rowId: 'speech-keep-loaded',
          title: l10n.settingsSttKeepLoaded,
          subtitle: memory == null
              ? l10n.settingsSttKeepLoadedSubtitle
              : '${l10n.settingsSttKeepLoadedSubtitle} $memory',
          trailing: settingsDropdown(
            context: context,
            value: mode,
            items: const ['automatic', 'always', 'after'],
            labels: [
              l10n.settingsSttKeepLoadedAutomatic,
              l10n.settingsSttKeepLoadedAlways,
              l10n.settingsSttKeepLoadedAfterIdle,
            ],
            keyPrefix: 'settings-stt-keep-loaded',
            onChanged: (value) => _store(switch (value) {
              'automatic' => kSttIdleAutomatic,
              'always' => 0,
              _ => minutes > 0 ? minutes : kSttIdleMinutesDefault,
            }),
          ),
        ),
        if (mode == 'after')
          WpSettingsRow(
            key: const ValueKey('settings-stt-keep-loaded-minutes'),
            rowId: 'speech-keep-loaded-minutes',
            title: l10n.settingsSttKeepLoadedUnloadAfter,
            trailing: settingsSlider(
              context: context,
              value: shownMinutes.toDouble(),
              min: kSttIdleMinutesMin.toDouble(),
              max: kSttIdleMinutesMax.toDouble(),
              divisions: kSttIdleMinutesMax - kSttIdleMinutesMin,
              valueLabel: l10n.settingsSttIdleTimeoutMinutes(shownMinutes),
              onChanged: (v) => setState(() => _dragMinutes = v.round()),
              onChangeEnd: (v) {
                setState(() => _dragMinutes = null);
                _store(v.round());
              },
            ),
          ),
      ],
    );
  }

  void _store(int minutes) {
    ref
        .read(settingsProvider.notifier)
        .updateSettings(
          (s) => s.copyWithSections(
            stt: s.stt.copyWith(idleTimeoutMinutes: minutes),
          ),
        );
  }
}
