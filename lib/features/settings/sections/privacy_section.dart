import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/data_key_access.dart';
import '../../../core/config/settings_provider.dart';
import '../../../core/config/settings_sections.dart'
    show kRetainedAudioCountStages;
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
import '../../onboarding/data_key_explanation.dart';
import '../data_key/data_key_flows.dart';
import '../data_key_backup_flow.dart';
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
      // Feedback of the data-key backup (saved, copied, failed).
      noticeArea: kDataKeyBackupNoticeArea,
      children: [
        WpSettingsRow(
          rowId: 'privacy-error-reporting',
          title: l10n.settingsErrorReporting,
          subtitle: errorReportingSubtitle,
          switchNamesRow: true,
          trailing: settingsToggle(
            label: l10n.settingsErrorReporting,
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
          switchNamesRow: true,
          trailing: settingsToggle(
            label: l10n.settingsShareUsageStats,
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
            settings.privacy.retainedAudioCount,
            kRetainedAudioMaxAge.inDays,
          ),
          switchNamesRow: true,
          trailing: settingsToggle(
            label: l10n.settingsRetainRecentAudio,
            value: settings.privacy.retainRecentAudio,
            onChanged: (v) {
              ref
                  .read(settingsProvider.notifier)
                  .updateSettings((s) => s.copyWith(retainRecentAudio: v));
            },
          ),
        ),
        WpSettingsRow(
          rowId: 'privacy-retained-audio-count',
          indent: true,
          title: l10n.settingsRetainedAudioCount,
          trailing: settingsDropdown(
            context: context,
            testId: 'privacy-retained-audio-count-dropdown',
            keyPrefix: 'privacy-retained-audio-count',
            value: '${settings.privacy.retainedAudioCount}',
            items: [
              for (final count in {
                ...kRetainedAudioCountStages,
                settings.privacy.retainedAudioCount,
              }.toList()..sort())
                '$count',
            ],
            onChanged: settings.privacy.retainRecentAudio
                ? (value) {
                    if (value == null) return;
                    ref
                        .read(settingsProvider.notifier)
                        .updateSettings(
                          (s) => s.copyWithSections(
                            privacy: s.privacy.copyWith(
                              retainedAudioCount: int.parse(value),
                            ),
                          ),
                        );
                  }
                : null,
          ),
        ),
        WpSettingsRow(
          rowId: 'privacy-failed-audio-keep',
          title: l10n.settingsFailedAudioKeep,
          // Stays pickable while retained audio is on (#1156): the choice is
          // saved and takes over once retention is off. The line says which
          // period applies meanwhile, instead of a menu of locked entries.
          subtitle: settings.privacy.retainRecentAudio
              ? '${l10n.settingsFailedAudioKeepSubtitle} '
                    '${l10n.settingsFailedAudioKeepOverridden(kRetainedAudioMaxAge.inDays)}'
              : l10n.settingsFailedAudioKeepSubtitle,
          trailing: _failedAudioKeepDropdown(
            context: context,
            l10n: l10n,
            days: settings.privacy.failedAudioKeepDays,
            onChanged: (days) => ref
                .read(settingsProvider.notifier)
                .updateSettings(
                  (s) => s.copyWithSections(
                    privacy: s.privacy.copyWith(failedAudioKeepDays: days),
                  ),
                ),
          ),
        ),
        const _DataKeyRow(),
        const _KeychainMigrationRow(),
        const _PendingAudioRows(),
      ],
    );
  }
}

/// Offers the announced move of the old keychain entries (#1163) again after
/// it was declined or postponed. Absent when nothing is pending.
class _KeychainMigrationRow extends ConsumerWidget {
  const _KeychainMigrationRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(legacyKeychainProvider);
    if (!state.hasPending) return const SizedBox.shrink();
    final l10n = L10n.of(context);
    return WpSettingsRow(
      rowId: 'privacy-keychain-migration',
      title: l10n.keychainMigrationTitle,
      subtitle: state.declined
          ? l10n.keychainMigrationDeclined
          : l10n.keychainMigrationBody,
      trailing: WpButton(
        testId: 'privacy-keychain-migration-retry',
        label: l10n.keychainMigrationAllow,
        variant: WpButtonVariant.secondary,
        onPressed: () => unawaited(runKeychainMigration(context, ref)),
      ),
    );
  }
}

/// The data-key row (#1165): what the key protects, its state and the one
/// action that state needs. "Back up" and "Restore" open the flows of
/// #1166/#1167; there is deliberately no "Delete": the key only goes together
/// with the data it protects, through the factory reset.
class _DataKeyRow extends ConsumerWidget {
  const _DataKeyRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final status = ref.watch(dataKeyAccessProvider);
    final parts = [l10n.dataKeyRowPurpose, dataKeyStatusText(l10n, status)];
    if (dataKeyStatusOffersBackup(status)) {
      parts.add(
        dataKeyBackupStatusText(l10n, ref.watch(dataKeyBackupProvider)),
      );
    }
    return WpSettingsRow(
      rowId: 'privacy-data-key',
      title: l10n.dataKeyTitle,
      subtitle: parts.join(' '),
      trailing: switch (status) {
        _ when dataKeyStatusOffersBackup(status) => dataKeyBackupButton(
          context: context,
          ref: ref,
          l10n: l10n,
          testId: 'privacy-data-key-backup',
        ),
        DataKeyAccessStatus.lost => WpButton(
          testId: 'privacy-data-key-restore',
          label: l10n.dataKeyRestore,
          variant: WpButtonVariant.secondary,
          onPressed: () =>
              unawaited(ref.read(dataKeyRestoreFlowProvider)(context)),
        ),
        _ => dataKeyAllowButton(
          ref: ref,
          l10n: l10n,
          status: status,
          testId: 'privacy-data-key-allow',
        ),
      },
    );
  }
}

/// Stages offered for the keep period of failed recordings, in days.
const kFailedAudioKeepStages = [1, 3, 7, 14, 30];

Widget _failedAudioKeepDropdown({
  required BuildContext context,
  required L10n l10n,
  required int days,
  required ValueChanged<int> onChanged,
}) {
  // A stored value outside the stages still shows as the current choice.
  final stages = {...kFailedAudioKeepStages, days}.toList()..sort();
  return settingsDropdown(
    context: context,
    testId: 'privacy-failed-audio-keep-dropdown',
    keyPrefix: 'privacy-failed-audio-keep',
    value: '$days',
    items: [for (final d in stages) '$d'],
    labels: [for (final d in stages) l10n.settingsHistoryAutoTrashDaysLabel(d)],
    onChanged: (v) {
      if (v == null) return;
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
