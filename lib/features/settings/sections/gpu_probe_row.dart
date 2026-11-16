/// Settings row for the out-of-process GPU check (`gpu_probe.dart`): shows
/// the stored result for this machine and lets the user run it again after a
/// driver or app update.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/hardware_info_service.dart' as hw;
import '../../../services/gpu_probe_process.dart';
import '../../../services/stt/whisper/gpu_probe.dart';
import '../widgets/wp_settings_group.dart';

class SttGpuProbeRow extends ConsumerStatefulWidget {
  const SttGpuProbeRow({super.key});

  @override
  ConsumerState<SttGpuProbeRow> createState() => _SttGpuProbeRowState();
}

class _SttGpuProbeRowState extends ConsumerState<SttGpuProbeRow> {
  GpuProbeRecord? _record;
  bool _read = false;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final service = ref.read(gpuProbeServiceProvider);
    // macOS: no probe runs there (see kGpuProbeSkippedOs), so no row either.
    if (!service.appliesHere) return const SizedBox.shrink();
    final gpu = ref.watch(hw.gpuInfoProvider).value;
    if (gpu == null || !gpu.hasGpu || gpu.optimalBackend == 'cpu') {
      return const SizedBox.shrink();
    }
    final key = service.keyFor(gpu: gpu, backend: gpu.optimalBackend);
    if (!_read) {
      _record = service.store.read(key.id);
      _read = true;
    }
    final record = _record;
    final subtitle = record == null
        ? l10n.settingsGpuProbeNotChecked
        : record.usable
        ? l10n.settingsGpuProbeUsable
        : l10n.settingsGpuProbeUnusable;

    return WpSettingsRow(
      rowId: 'speech-gpu-probe',
      title: l10n.settingsGpuProbeTitle,
      subtitle: subtitle,
      trailing: Semantics(
        identifier: 'settings-gpu-probe-retry',
        label: l10n.settingsGpuProbeRetry,
        button: true,
        child: IconButton(
          key: const ValueKey('settings-gpu-probe-retry'),
          icon: const Icon(LucideIcons.refreshCw, size: WpIconSize.sm),
          tooltip: l10n.settingsGpuProbeRetry,
          onPressed: () {
            service.retry(key);
            setState(() {
              _record = null;
              _read = true;
            });
          },
        ),
      ),
    );
  }
}
