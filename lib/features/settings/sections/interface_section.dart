/// General settings card (WP-23b): app language, autostart, notifications and
/// close-to-tray. Appearance and the side panel live in
/// [InterfaceAppearanceSection]. The sponsor-chip switch moved to the Help page
/// ([SponsorChipRow]).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/settings_provider.dart';
import '../../../core/first_steps/first_steps_notifier.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/l10n/locale_native_name.dart';
import '../../../core/logging/app_logger.dart';
import '../../../services/autostart_service.dart';
import '../../../widgets/autostart_approval_hint.dart';
import '../../../services/support/support_state.dart';
import '../../../services/review_prompt_service.dart';
import '../../../services/telemetry_service.dart';
import '../../../widgets/language_selector.dart';
import '../../../widgets/wp_button.dart';
import '../settings_widgets.dart';
import '../widgets/wp_settings_group.dart';

class InterfaceGeneralSection extends ConsumerWidget {
  const InterfaceGeneralSection({super.key});

  static final _log = AppLogger('InterfaceSection');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
    final reviewPromptOptedOut =
        ref.watch(reviewPromptOptOutProvider).value ?? false;
    final firstStepsCanShowAgain = ref.watch(
      firstStepsViewProvider.select((view) => view.canShowAgain),
    );
    final autostartSyncError = ref.watch(autostartSyncFailureProvider);
    final autostartApprovalNeeded = ref.watch(autostartApprovalNeededProvider);
    // Both trailing dropdowns of this group take their width from the same
    // label set (see SharedWidthDropdown), so they match by construction.
    const locales = L10n.supportedLocales;
    final autostartValue = !settings.launchAtStartup
        ? 'never'
        : settings.startMinimized
        ? 'minimized'
        : 'normal';
    final autostartLabels = [
      l10n.settingsAutostartNever,
      l10n.settingsAutostartNormal,
      l10n.settingsAutostartMinimized,
    ];
    final dropdownLabels = [
      for (final locale in locales) localeNativeName(locale),
      ...autostartLabels,
    ];

    return WpSettingsGroup(
      heading: l10n.settingsInterface,
      children: [
        WpSettingsRow(
          rowId: 'general-app-language',
          title: l10n.settingsAppLanguage,
          trailing: SharedWidthDropdown(
            labels: dropdownLabels,
            selectedLabel: localeNativeName(
              locales.firstWhere(
                (l) => l.languageCode == settings.locale,
                orElse: () => locales.first,
              ),
            ),
            child: WpLanguageSelector(
              currentLocale: settings.locale,
              onChanged: (code) {
                ref
                    .read(settingsProvider.notifier)
                    .updateSettings((s) => s.copyWith(locale: code));
                try {
                  ref.read(telemetryProvider).trackSettingChange('language');
                } catch (e) {
                  _log.debug('telemetry failed: $e');
                }
              },
            ),
          ),
        ),
        WpSettingsRow(
          rowId: 'general-autostart',
          title: l10n.settingsLaunchAtStartup,
          trailing: SharedWidthDropdown(
            labels: dropdownLabels,
            selectedLabel: switch (autostartValue) {
              'normal' => l10n.settingsAutostartNormal,
              'minimized' => l10n.settingsAutostartMinimized,
              _ => l10n.settingsAutostartNever,
            },
            child: settingsDropdown(
              context: context,
              value: autostartValue,
              items: const ['never', 'normal', 'minimized'],
              expanded: true,
              labels: autostartLabels,
              onChanged: (v) {
                final (launch, minimized) = switch (v) {
                  'normal' => (true, false),
                  'minimized' => (true, true),
                  _ => (false, false),
                };
                ref
                    .read(settingsProvider.notifier)
                    .updateSettings(
                      // Compatibility write until legacy autostart fields are
                      // removed from AppSettings.copyWith.
                      // ignore: deprecated_member_use
                      (s) => s.copyWith(
                        launchAtStartup: launch,
                        startMinimized: minimized,
                      ),
                    );
              },
            ),
          ),
        ),
        if (autostartSyncError != null)
          SettingsRowFrame(
            rowId: 'general-autostart-error',
            child: _AutostartSyncFailureNotice(
              message: l10n.settingsAutostartSyncFailed,
              onRetry: () =>
                  ref.read(autostartServiceProvider.notifier).retrySync(),
            ),
          ),
        // Only a child while macOS holds the login item back. The group puts a
        // divider before and after every child, and the hint renders nothing
        // otherwise, which stacked two dividers under the autostart row.
        if (autostartApprovalNeeded) const WpAutostartApprovalHint(),
        WpSettingsRow(
          rowId: 'general-notifications',
          title: l10n.settingsShowNotifications,
          subtitle: l10n.settingsShowNotificationsSubtitle,
          semanticToggledValue: settings.showNotifications,
          trailing: settingsToggle(
            value: settings.showNotifications,
            onChanged: (v) => ref
                .read(settingsProvider.notifier)
                .updateSettings((s) => s.copyWith(showNotifications: v)),
          ),
        ),
        WpSettingsRow(
          rowId: 'general-close-to-tray',
          title: l10n.settingsCloseToTray,
          subtitle: l10n.settingsCloseToTraySubtitle,
          semanticToggledValue: settings.closeToTray,
          trailing: settingsToggle(
            key: const ValueKey('interface-close-to-tray'),
            value: settings.closeToTray,
            onChanged: (v) => ref
                .read(settingsProvider.notifier)
                .updateSettings((s) => s.copyWith(closeToTray: v)),
          ),
        ),
        // Only after "Don't ask again" on the rating reminder; the switch goes
        // away once it is turned back on.
        if (reviewPromptOptedOut) const ReviewPromptRestoreRow(),
        // Brings the "Erste Schritte" card back after it was closed. Only
        // while the card has something to show (see firstStepsCanShowAgain).
        if (firstStepsCanShowAgain) const FirstStepsRestoreRow(),
      ],
    );
  }
}

/// Inline warning shown when [AutostartService] failed to register the
/// "Launch at Startup" setting with the OS.
///
/// This comment used to claim it reused the pattern of the stable-revert hint
/// in `updates_section.dart`; the two were in fact laid out differently, and a
/// third notice differed again. They now genuinely share one implementation
/// ([settingsInlineNotice]), so the claim is finally true by construction.
///
/// No dismiss action: this reflects the live sync outcome, not a one-time tip,
/// so it clears itself once a later sync succeeds. "Try again" runs that sync
/// once more (UIA-SET-14).
class _AutostartSyncFailureNotice extends StatelessWidget {
  const _AutostartSyncFailureNotice({
    required this.message,
    required this.onRetry,
  });

  final String message;

  /// Runs the sync again; the notice clears itself if that succeeds.
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => settingsInlineNotice(
    context: context,
    message: message,
    action: Align(
      alignment: AlignmentDirectional.centerStart,
      child: WpButton(
        key: const Key('autostartRetryButton'),
        label: L10n.of(context).actionRetry,
        variant: WpButtonVariant.secondary,
        onPressed: onRetry,
      ),
    ),
  );
}

/// Switch that lifts a "Don't ask again" choice for the rating reminder. It
/// shows off, and turning it on only removes the permanent opt-out.
class ReviewPromptRestoreRow extends ConsumerWidget {
  const ReviewPromptRestoreRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    return WpSettingsRow(
      rowId: 'general-review-prompt-restore',
      title: l10n.settingsReviewPromptRestore,
      subtitle: l10n.settingsReviewPromptRestoreSubtitle,
      semanticToggledValue: false,
      trailing: settingsToggle(
        key: const ValueKey('interface-review-prompt-restore'),
        value: false,
        onChanged: (_) async {
          await clearReviewPromptOptOut();
          ref.invalidate(reviewPromptOptOutProvider);
        },
      ),
    );
  }
}

/// "Neu anzeigen" for the "Erste Schritte" card: clears the dismissal and keeps
/// every confirmed item.
class FirstStepsRestoreRow extends ConsumerWidget {
  const FirstStepsRestoreRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    return WpSettingsRow(
      rowId: 'general-first-steps-restore',
      title: l10n.firstStepsRestoreTitle,
      subtitle: l10n.firstStepsRestoreSubtitle,
      trailing: WpButton(
        testId: 'interface-first-steps-restore',
        label: l10n.firstStepsRestoreAction,
        variant: WpButtonVariant.secondary,
        onPressed: () =>
            ref.read(firstStepsNotifierProvider.notifier).showAgain(),
      ),
    );
  }
}

/// The sponsor-chip switch, shown on the Help page (Hilfe) next to the support
/// card. Showing the chip again is always allowed; hiding it is gated by
/// [SupportStatus.suppressesPrompts].
class SponsorChipRow extends ConsumerWidget {
  const SponsorChipRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final support = ref.watch(supportStatusProvider);
    return WpSettingsRow(
      rowId: 'general-sponsor-chip',
      title: l10n.settingsSponsorChip,
      subtitle: l10n.settingsSponsorChipSubtitle,
      semanticToggledValue: support.showsSponsorChip,
      trailing: settingsToggle(
        key: const ValueKey('settings-sponsor-chip-restore'),
        value: support.showsSponsorChip,
        // Hiding and showing the chip again are both allowed for every user
        // (growth review R-12).
        onChanged: !support.showsSponsorChip
            ? (_) => ref.read(supportStatusProvider.notifier).restoreChip()
            : (_) => ref.read(supportStatusProvider.notifier).hideChip(),
      ),
    );
  }
}
