import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/logging/crash_reporter.dart';
import '../../../services/telemetry_service.dart';
import '../../../widgets/section.dart';
import '../settings_widgets.dart';

class PrivacySection extends ConsumerWidget {
  const PrivacySection({super.key});

  static final _log = AppLogger('PrivacySection');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
    // Re-enabling cannot start Sentry mid-session; say so instead of
    // pretending the toggle already took effect.
    final errorReportingSubtitle =
        CrashReporter.instance?.restartRequired ?? false
        ? '${l10n.settingsErrorReportingSubtitle} '
              '${l10n.settingsErrorReportingRestartHint}'
        : l10n.settingsErrorReportingSubtitle;

    return WpSection(
      title: l10n.settingsPrivacy,
      subtitle: l10n.settingsPrivacySubtitle,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          SettingRow(
            icon: LucideIcons.shieldCheck,
            label: l10n.settingsErrorReporting,
            subtitle: errorReportingSubtitle,
            semanticToggledValue: settings.errorReporting,
            trailing: settingsToggle(
              value: settings.errorReporting,
              onChanged: (v) {
                // Before the settings rebuild, so the subtitle sees it.
                CrashReporter.instance?.consentGranted = v;
                ref
                    .read(settingsProvider.notifier)
                    .updateSettings((s) => s.copyWith(errorReporting: v));
                try {
                  ref
                      .read(telemetryProvider)
                      .trackSettingChange('error_reporting');
                } catch (e) {
                  _log.debug('telemetry failed: $e');
                }
              },
            ),
          ),
          SettingRow(
            icon: LucideIcons.barChart3,
            label: l10n.settingsShareUsageStats,
            subtitle: l10n.settingsShareUsageStatsSubtitle,
            semanticToggledValue: settings.privacy.shareUsageStats,
            trailing: settingsToggle(
              value: settings.privacy.shareUsageStats,
              onChanged: (v) {
                if (!v) {
                  // Deactivating: fire the opt-out event while consent is still
                  // active, before updateSettings revokes it.
                  try {
                    ref
                        .read(telemetryProvider)
                        .trackSettingChange('share_usage_stats');
                  } catch (e) {
                    _log.debug('telemetry failed: $e');
                  }
                }
                ref
                    .read(settingsProvider.notifier)
                    .updateSettings((s) => s.copyWith(shareUsageStats: v));
                if (v) {
                  // Activating: persist first so the telemetry provider
                  // reflects the new consent before firing the event.
                  try {
                    ref
                        .read(telemetryProvider)
                        .trackSettingChange('share_usage_stats');
                  } catch (e) {
                    _log.debug('telemetry failed: $e');
                  }
                }
              },
            ),
          ),
          SettingRow(
            icon: LucideIcons.fileAudio,
            label: l10n.settingsRetainRecentAudio,
            subtitle: l10n.settingsRetainRecentAudioSubtitle,
            semanticToggledValue: settings.privacy.retainRecentAudio,
            trailing: settingsToggle(
              value: settings.privacy.retainRecentAudio,
              onChanged: (v) {
                ref
                    .read(settingsProvider.notifier)
                    .updateSettings((s) => s.copyWith(retainRecentAudio: v));
              },
            ),
          ),
        ],
      ),
    );
  }
}
