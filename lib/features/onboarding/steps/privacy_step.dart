import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/telemetry_service.dart';
import '../../../widgets/wp_accent_button.dart';
import '../../settings/settings_widgets.dart';

/// Widget key exposed for testing.
@visibleForTesting
const kPrivacyStepCrashToggleKey = Key('privacyStepCrashReportingToggle');

/// Onboarding Step 2 — informed telemetry opt-out.
///
/// Tells the user, up front, that WhisPaste sends anonymous, GDPR-compliant
/// usage statistics to an EU server, and separately, that it can send
/// anonymous crash reports — and gives them both toggles right here. Both
/// stay **on by default** (informed opt-out; [AppSettings] defaults
/// `shareUsageStats = true` and `errorReporting = true`); the user can switch
/// either off without leaving the flow. Wording and toggles mirror
/// Settings → Privacy ([PrivacySection]) so the two never drift. Continuing
/// is always allowed regardless of either toggle's state.
class PrivacyStep extends ConsumerWidget {
  const PrivacyStep({super.key, required this.onNext, required this.onBack});

  final VoidCallback onNext;
  final VoidCallback onBack;

  static final _log = AppLogger('OnboardingPrivacy');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = L10n.of(context);

    final textPrimary = isDark
        ? WpColorsDark.textPrimary
        : WpColorsLight.textPrimary;
    final textSecondary = isDark
        ? WpColorsDark.textSecondary
        : WpColorsLight.textSecondary;
    final accentGradient = isDark
        ? WpColorsDark.accentWarmGradient
        : WpColorsLight.accentWarmGradient;
    final surfaceVariant =
        (isDark ? WpColorsDark.surfaceVariant : WpColorsLight.surfaceVariant)
            .withValues(alpha: 0.55);
    final borderColor = isDark
        ? WpColorsDark.borderSubtle
        : WpColorsLight.borderSubtle;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.onboardingPrivacyTitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: WpTypography.headline,
            fontWeight: FontWeight.bold,
            color: textPrimary,
          ),
        ),
        const SizedBox(height: WpSpacing.sm),

        Text(
          l10n.onboardingPrivacyHint,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: WpTypography.subheading,
            color: textSecondary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: WpSpacing.xxl),

        // Opt-out toggles — same SettingRow + switch as Settings → Privacy.
        // Two separate consents (analytics vs. crash reports), each its own
        // toggle, each on by default.
        Container(
          decoration: BoxDecoration(
            color: surfaceVariant,
            borderRadius: WpRadius.borderLg,
            border: Border.all(color: borderColor),
          ),
          padding: const EdgeInsets.symmetric(horizontal: WpSpacing.sm),
          child: Column(
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
        ),
        const SizedBox(height: WpSpacing.xxl),

        Row(
          children: [
            TextButton(
              onPressed: onBack,
              child: Text(
                l10n.onboardingBack,
                style: TextStyle(color: textSecondary),
              ),
            ),
            const Spacer(),
            SizedBox(
              width: 140,
              // loam-ignore: a11y-interactive-semantics – semantics provided in WpAccentButton.build
              child: WpAccentButton(
                label: l10n.onboardingNext,
                gradient: accentGradient,
                onPressed: onNext,
              ),
            ),
          ],
        ),
      ],
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
