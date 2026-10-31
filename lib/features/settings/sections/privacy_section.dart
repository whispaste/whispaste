import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/settings_provider.dart';
import '../../../core/data/database.dart' show kAudioCap;
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/logging/crash_reporter.dart';
import '../../../services/audio/retention/audio_retention.dart'
    show kRetainedAudioMaxAge;
import '../../../services/pending_audio/kept_until_format.dart';
import '../../../services/pending_audio/pending_audio_providers.dart';
import '../../../services/telemetry_service.dart';
import '../../../widgets/wp_button.dart';
import '../../../widgets/recording_behavior.dart' show localizeRecordingError;
import '../settings_widgets.dart';
import '../widgets/wp_settings_group.dart';

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

    return WpSettingsGroup(
      heading: l10n.settingsPrivacy,
      children: [
        WpSettingsRow(
          rowId: 'privacy-error-reporting',
          title: l10n.settingsErrorReporting,
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
        WpSettingsRow(
          rowId: 'privacy-usage-stats',
          title: l10n.settingsShareUsageStats,
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
        WpSettingsRow(
          rowId: 'privacy-retain-audio',
          title: l10n.settingsRetainRecentAudio,
          subtitle: l10n.settingsRetainRecentAudioSubtitle(
            kAudioCap,
            kRetainedAudioMaxAge.inDays,
          ),
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
        WpSettingsRow(
          rowId: 'privacy-failed-audio-keep',
          title: l10n.settingsFailedAudioKeep,
          subtitle: l10n.settingsFailedAudioKeepSubtitle,
          disabledReason: settings.privacy.retainRecentAudio
              ? l10n.settingsFailedAudioKeepDisabled(
                  kRetainedAudioMaxAge.inDays,
                )
              : null,
          trailing: _failedAudioKeepDropdown(
            context: context,
            l10n: l10n,
            days: settings.privacy.failedAudioKeepDays,
            enabled: !settings.privacy.retainRecentAudio,
            onChanged: (days) => ref
                .read(settingsProvider.notifier)
                .updateSettings(
                  (s) => s.copyWithSections(
                    privacy: s.privacy.copyWith(failedAudioKeepDays: days),
                  ),
                ),
          ),
        ),
        const _PendingAudioRows(),
      ],
    );
  }
}

/// Stages offered for the keep period of failed recordings, in days.
const kFailedAudioKeepStages = [1, 3, 7, 14, 30];

Widget _failedAudioKeepDropdown({
  required BuildContext context,
  required L10n l10n,
  required int days,
  required bool enabled,
  required ValueChanged<int> onChanged,
}) {
  // A stored value outside the stages still shows as the current choice.
  final stages = {...kFailedAudioKeepStages, days}.toList()..sort();
  return settingsDropdown(
    context: context,
    testId: 'privacy-failed-audio-keep-dropdown',
    value: '$days',
    items: [for (final d in stages) '$d'],
    labels: [for (final d in stages) l10n.settingsHistoryAutoTrashDaysLabel(d)],
    disabledItems: enabled ? null : {for (final d in stages) '$d'},
    onChanged: (v) {
      if (!enabled || v == null) return;
      onChanged(int.parse(v));
    },
  );
}

/// Settings rows for recordings whose transcription failed and that wait for
/// a retry (UIA-FLW-01). Each can be discarded.
class _PendingAudioRows extends ConsumerWidget {
  const _PendingAudioRows();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final entries = ref.watch(pendingRetryListProvider).value ?? const [];
    return Column(
      children: [
        WpSettingsRow(
          rowId: 'privacy-pending-audio',
          title: l10n.pendingAudioSectionTitle,
          subtitle:
              '${l10n.pendingAudioSectionBody} '
              '${l10n.pendingAudioRetentionNote}'
              // The empty state belongs to this row, not to a row of its own
              // that search would have to list.
              '${entries.isEmpty ? '\n${l10n.pendingAudioEmpty}' : ''}',
          trailing: const SizedBox.shrink(),
        ),
        for (final entry in entries)
          WpSettingsRow(
            rowId: 'privacy-pending-audio-${entry.entryId}',
            title: localizeRecordingError(l10n, entry.errorCode),
            subtitle:
                '${TimeOfDay.fromDateTime(entry.capturedAt).format(context)}\n'
                '${l10n.pendingAudioKeptUntil(formatKeptUntil(Localizations.localeOf(context).toString(), entry.expiresAt))}',
            subtitleKey: ValueKey(
              'privacy-pending-audio-kept-until-${entry.entryId}',
            ),
            trailing: WpButton(
              key: ValueKey('privacy-pending-audio-discard-${entry.entryId}'),
              label: l10n.recoveryDiscard,
              variant: WpButtonVariant.ghost,
              onPressed: () async {
                await ref
                    .read(pendingAudioQueueProvider)
                    .discard(entry.entryId);
                ref.invalidate(pendingRetryListProvider);
              },
            ),
          ),
      ],
    );
  }
}
