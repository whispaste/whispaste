/// Updates settings section — consolidates every update-related control in
/// one place: the automatic update check (`checkUpdates`) and the release
/// channel toggle (`beta`/`stable`).
///
/// Store builds have no self-updater and no release channel at all (PRD §6.3:
/// stores are stable-only), so the whole section hides for
/// [DeployChannel.store] — AC „Store-Build blendet den Toggle sinnvoll aus".
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/logging/app_logger.dart';
import '../../../services/deploy_channel_service.dart';
import '../../../services/telemetry_service.dart';
import '../../../services/update_channel_service.dart';
import '../../../widgets/section.dart';
import '../settings_widgets.dart';

class UpdatesSection extends ConsumerWidget {
  const UpdatesSection({super.key});

  static final _log = AppLogger('UpdatesSection');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
    final channel = ref.watch(deployChannelProvider);

    // Store builds: no self-updater, no release channel → hide the section
    // entirely rather than rendering an empty shell.
    if (channel == DeployChannel.store) return const SizedBox.shrink();

    final updateChannel =
        ref.watch(updateChannelProvider).value ?? UpdateChannel.stable;
    final isBeta = updateChannel == UpdateChannel.beta;

    return WpSection(
      title: l10n.settingsUpdates,
      subtitle: l10n.settingsUpdatesSubtitle,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          SettingRow(
            icon: LucideIcons.refreshCw,
            label: l10n.settingsCheckUpdates,
            subtitle: l10n.settingsCheckUpdatesSubtitle,
            semanticToggledValue: settings.updates.checkUpdates,
            trailing: settingsToggle(
              value: settings.updates.checkUpdates,
              onChanged: (v) {
                ref
                    .read(settingsProvider.notifier)
                    .updateSettings((s) => s.copyWith(checkUpdates: v));
                try {
                  ref
                      .read(telemetryProvider)
                      .trackSettingChange('check_updates');
                } catch (e) {
                  _log.debug('telemetry failed: $e');
                }
              },
            ),
          ),
          SettingRow(
            icon: LucideIcons.flaskConical,
            label: l10n.settingsBetaUpdates,
            subtitle: l10n.settingsBetaUpdatesSubtitle,
            semanticToggledValue: isBeta,
            trailing: settingsToggle(
              value: isBeta,
              onChanged: (v) {
                ref
                    .read(updateChannelProvider.notifier)
                    .setChannel(v ? UpdateChannel.beta : UpdateChannel.stable);
                try {
                  ref
                      .read(telemetryProvider)
                      .trackSettingChange('beta_updates');
                } catch (e) {
                  _log.debug('telemetry failed: $e');
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
