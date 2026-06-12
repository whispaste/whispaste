/// GPU/CPU override settings section.
///
/// Lets advanced users override whether the local speech service uses GPU
/// or CPU — bound to the existing [GpuAcceleration] enum persisted in
/// [BehaviorSettings.gpuAcceleration]. No new state is introduced.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/settings_enums.dart';
import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../widgets/section.dart';
import '../settings_widgets.dart';

// ---------------------------------------------------------------------------
// Graphics Acceleration section
// ---------------------------------------------------------------------------

class GpuAccelerationSection extends ConsumerWidget {
  const GpuAccelerationSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;

    return WpSection(
      title: l10n.settingsGpuAcceleration,
      subtitle: l10n.settingsGpuAccelerationSubtitle,
      padding: EdgeInsets.zero,
      child: SettingRow(
        icon: LucideIcons.zap,
        label: l10n.settingsGpuAcceleration,
        trailing: settingsDropdown(
          context: context,
          value: settings.behavior.gpuAcceleration,
          items: GpuAcceleration.values.map((e) => e.value).toList(),
          labels: [
            l10n.settingsGpuAccelerationAuto,
            l10n.settingsGpuAccelerationEnabled,
            l10n.settingsGpuAccelerationDisabled,
          ],
          onChanged: (v) => ref
              .read(settingsProvider.notifier)
              .updateSettings(
                (s) => s.copyWithSections(
                  behavior: s.behavior.copyWith(gpuAcceleration: v!),
                ),
              ),
        ),
      ),
    );
  }
}
