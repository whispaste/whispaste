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

/// Onboarding Step 2 — informed telemetry opt-out.
///
/// Tells the user, up front, that WhisPaste sends anonymous, GDPR-compliant
/// usage statistics to an EU server — and gives them the toggle right here.
/// Consent stays **on by default** (informed opt-out, [AppSettings] default
/// `shareUsageStats = true`); the user can switch it off without leaving the
/// flow. Wording and the toggle mirror Settings → Privacy so the two never
/// drift. Continuing is always allowed regardless of the toggle state.
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

        // Opt-out toggle — same SettingRow + switch as Settings → Privacy.
        Container(
          decoration: BoxDecoration(
            color: surfaceVariant,
            borderRadius: WpRadius.borderLg,
            border: Border.all(color: borderColor),
          ),
          padding: const EdgeInsets.symmetric(horizontal: WpSpacing.sm),
          child: SettingRow(
            icon: LucideIcons.barChart3,
            label: l10n.onboardingPrivacyToggle,
            subtitle: l10n.onboardingPrivacyToggleHint,
            semanticToggledValue: settings.privacy.shareUsageStats,
            trailing: settingsToggle(
              value: settings.privacy.shareUsageStats,
              onChanged: (v) => _setConsent(ref, v),
            ),
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
  void _setConsent(WidgetRef ref, bool value) {
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
}
