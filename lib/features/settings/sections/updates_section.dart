/// Updates settings section: the automatic update check (`checkUpdates`). The
/// manual check moved to the About area (ticket), where the version and the
/// update status are.
///
/// Store builds have no self-updater.
/// The same applies to package-manager-managed installs (Homebrew Cask,
/// Scoop) — see [isExternallyManaged].
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/logging/app_logger.dart';
import '../../../services/auto_updater_service.dart';
import '../../../services/deploy_channel_service.dart';
import '../../../services/telemetry_service.dart';
import '../../../services/update_actions.dart';
import '../settings_widgets.dart';
import '../widgets/wp_settings_group.dart';

class UpdatesSection extends ConsumerWidget {
  const UpdatesSection({super.key});

  static final _log = AppLogger('UpdatesSection');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
    final channel = ref.watch(deployChannelProvider);

    // Package-managed builds (Homebrew, Scoop, Snap, Flatpak): the package
    // manager owns updates, so the section stays hidden. Store builds keep
    // the rows, disabled with their reason (ticket, AR-19).
    if (channel == DeployChannel.packageManaged) {
      return const SizedBox.shrink();
    }
    final storeBuild = channel == DeployChannel.store;

    return WpSettingsGroup(
      heading: l10n.settingsUpdates,
      children: [
        WpSettingsRow(
          rowId: 'general-updates-auto',
          title: l10n.settingsCheckUpdates,
          subtitle: storeBuild
              ? l10n.settingsStoreUpdatesUnavailable
              : updatesInstalledByHand(
                  channel,
                  autoUpdater: shouldUseAutoUpdater(channel),
                )
              ? l10n.settingsCheckUpdatesSubtitleManualInstall
              : l10n.settingsCheckUpdatesSubtitle,
          switchNamesRow: true,
          trailing: settingsToggle(
            label: l10n.settingsCheckUpdates,
            key: const ValueKey('settings-updates-check-toggle'),
            value: settings.updates.checkUpdates,
            onChanged: storeBuild
                ? null
                : (v) {
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
      ],
    );
  }
}
