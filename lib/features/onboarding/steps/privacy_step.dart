import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/telemetry_service.dart';
import '../../settings/settings_widgets.dart';
import 'onboarding_headings.dart';
import 'onboarding_page_fill.dart';

/// Widget key exposed for testing.
@visibleForTesting
const kPrivacyStepCrashToggleKey = Key('privacyStepCrashReportingToggle');

/// Onboarding Step 2 — informed telemetry opt-out.
///
/// Tells the user, up front, that audio and text stay local and that
/// WhisPaste sends anonymous, GDPR-compliant usage statistics to a
/// self-hosted EU server (CONTEXT.md §6.5/§7: never an absolute "no
/// tracking" claim), and separately, that it can send anonymous crash
/// reports — and gives them both toggles right here. Both
/// stay **on by default** (informed opt-out; [AppSettings] defaults
/// `shareUsageStats = true` and `errorReporting = true`); the user can switch
/// either off without leaving the flow. Wording and toggles mirror
/// Settings → Privacy ([PrivacySection]) so the two never drift. Continuing
/// is always allowed regardless of either toggle's state. Content only —
/// navigation (Back/Next) is owned by the onboarding shell.
class PrivacyStep extends ConsumerWidget {
  const PrivacyStep({super.key});

  static final _log = AppLogger('OnboardingPrivacy');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
    final l10n = L10n.of(context);

    return OnboardingPage(
      header: OnboardingPageHeading(
        title: l10n.onboardingPrivacyTitle,
        subtitle: l10n.onboardingPrivacyHint,
      ),

      // Opt-out toggles — same SettingRow + switch as Settings → Privacy.
      // Two separate consents (analytics vs. crash reports), each its own
      // toggle, each on by default. Deliberately frameless: the surrounding
      // card plus an inline divider made two quiet rows read as one packed
      // box. Whitespace separates them now, as in the reference.
      //
      // The pair is one body block, so this page's ~206 px of spare height
      // (511-px content area) goes above and below it, never between the
      // two rows: they are separate decisions but the same kind of
      // decision, and a gap as wide as the one under the heading would stop
      // them reading as a pair. See [OnboardingPageBody].
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingRow(
            icon: LucideIcons.barChart3,
            label: l10n.onboardingPrivacyToggle,
            subtitle: l10n.onboardingPrivacyToggleHint,
            semanticToggledValue: settings.privacy.shareUsageStats,
            trailing: settingsToggle(
              value: settings.privacy.shareUsageStats,
              onChanged: (v) => _setUsageStatsConsent(ref, v),
            ),
          ),
          const SizedBox(height: WpSpacing.lg),
          SettingRow(
            key: kPrivacyStepCrashToggleKey,
            icon: LucideIcons.shieldCheck,
            label: l10n.onboardingPrivacyCrashToggle,
            subtitle: l10n.onboardingPrivacyCrashToggleHint,
            semanticToggledValue: settings.errorReporting,
            trailing: settingsToggle(
              value: settings.errorReporting,
              onChanged: (v) => _setErrorReportingConsent(ref, v),
            ),
          ),
        ],
      ),
    );
  }

  /// Persists the consent flag and fires the categorical opt-in/opt-out signal
  /// in the correct order: when revoking, send the event *before* consent is
  /// cleared (otherwise the telemetry gate drops it); when granting, persist
  /// first so the provider reflects the new consent before the event fires.
  /// Mirrors [PrivacySection] exactly so the two paths never diverge.
  void _setUsageStatsConsent(WidgetRef ref, bool value) {
    if (!value) {
      try {
        ref.read(telemetryProvider).trackSettingChange('share_usage_stats');
      } catch (e) {
        _log.debug('telemetry failed: $e');
      }
    }
    ref
        .read(settingsProvider.notifier)
        .updateSettings((s) => s.copyWith(shareUsageStats: value));
    if (value) {
      try {
        ref.read(telemetryProvider).trackSettingChange('share_usage_stats');
      } catch (e) {
        _log.debug('telemetry failed: $e');
      }
    }
  }

  /// Persists crash-reporting consent. Unlike usage stats, this toggle does
  /// not gate the telemetry channel that reports it, so there is no
  /// before/after ordering concern — mirrors [PrivacySection]'s
  /// `errorReporting` handler exactly.
  void _setErrorReportingConsent(WidgetRef ref, bool value) {
    ref
        .read(settingsProvider.notifier)
        .updateSettings((s) => s.copyWith(errorReporting: value));
    try {
      ref.read(telemetryProvider).trackSettingChange('error_reporting');
    } catch (e) {
      _log.debug('telemetry failed: $e');
    }
  }
}
