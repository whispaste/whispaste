import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/app_urls.dart';
import '../../../core/config/settings_enums.dart';
import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/logging/crash_reporter.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/telemetry_service.dart';
import '../../../widgets/external_link.dart';
import '../../../widgets/wp_button.dart';
import '../../../widgets/wp_hero_button.dart';
import '../../settings/settings_widgets.dart';
import '../onboarding_split_page.dart';

/// Widget keys exposed for testing.
@visibleForTesting
const kPrivacyStepCrashToggleKey = Key('privacy-step-crash-reporting-toggle');
const kPrivacyStepUsageToggleKey = Key('privacy-step-usage-stats-toggle');

/// Key of the privacy page itself (test and ID anchor, `onboarding-privacy-*`).
const kPrivacyStepPageKey = ValueKey('onboarding-privacy-page');

/// The sentence that says where the user's audio goes, bound to the chosen
/// transcription mode (CONTEXT.md §6.5/§7: never an absolute claim).
///
/// Local mode keeps audio and text on the device; a cloud provider or the
/// user's own server receives the audio directly, never through WhisPaste
/// servers. A custom server is named by its host only — never a path, query
/// or key. Without a usable host there is no sentence rather than a wrong one.
String? onboardingPrivacyModeLine(L10n l10n, AppSettings settings) {
  switch (settings.sttProviderType) {
    case SttProviderType.onDevice:
      return l10n.onboardingPrivacyModeLocal;
    case SttProviderType.openAI:
    case SttProviderType.deepgram:
      return l10n.onboardingPrivacyModeCloud(settings.sttProviderType.value);
    case SttProviderType.customEndpoint:
      final host = Uri.tryParse(
        settings.cloudProvider.customEndpointUrl.trim(),
      )?.host;
      if (host == null || host.isEmpty) return null;
      return l10n.onboardingPrivacyModeCustom(host);
  }
}

/// Onboarding v6 screen 7, the closing page: "ready to dictate", where the
/// audio goes, and the two diagnostics switches — usage statistics and crash
/// reports — with the same texts as Settings → Privacy ([PrivacySection]), so
/// the two never drift. Keeping recordings is not asked here; the page points
/// to Settings for it (maintainer 2026-10-30). Its primary action starts
/// WhisPaste ("Modell laden" without a model, "Hotkey ändern" on a confirmed
/// conflict; the overlay decides). The switches are the choice the privacy
/// hold waits for; the overlay commits it when the flow completes.
class PrivacyStep extends ConsumerWidget {
  const PrivacyStep({
    super.key,
    this.primaryKey,
    this.nextLabel,
    this.nextTestId = 'onboarding-nav-next',
    this.onNext,
    this.onBack,
    this.needsModel = false,
  });

  final Key? primaryKey;
  final String? nextLabel;
  final String nextTestId;
  final VoidCallback? onNext;
  final VoidCallback? onBack;

  /// No speech model yet: the heading says "almost ready", matching the
  /// "Modell laden" action, instead of promising a dictation that cannot run.
  final bool needsModel;

  static final _log = AppLogger('OnboardingPrivacy');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
    final l10n = L10n.of(context);
    final modeLine = onboardingPrivacyModeLine(l10n, settings);
    final muted = TextStyle(
      fontSize: WpTypography.small,
      height: 1.4,
      color: WpColors.textMuted,
    );

    return OnboardingSplitPage(
      panelAsset: 'assets/onboarding/privacy-glacier.webp',
      panel: const _ClosingScene(),
      copy: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onBack != null)
            OnboardingBackLink(
              testId: 'onboarding-privacy-back',
              label: l10n.onboardingBack,
              onPressed: onBack!,
            ),
          OnboardingSplitHeading(
            needsModel
                ? l10n.onboardingPrivacyAlmostReadyTitle
                : l10n.onboardingPrivacyReadyTitle,
            testId: 'onboarding-privacy-heading',
          ),
          if (modeLine != null) ...[
            const SizedBox(height: WpSpacing.sm),
            Semantics(
              identifier: 'onboarding-privacy-mode-line',
              child: Text(
                modeLine,
                style: TextStyle(
                  fontSize: WpTypography.body,
                  height: 1.45,
                  color: WpColors.textSecondary,
                ),
              ),
            ),
          ],
          const SizedBox(height: WpSpacing.lg),
          SettingRow(
            testId: 'onboarding-privacy-usage-row',
            icon: LucideIcons.barChart3,
            iconSize: WpIconSize.md,
            label: l10n.settingsShareUsageStats,
            subtitle: l10n.settingsShareUsageStatsSubtitle,
            semanticToggledValue: settings.privacy.shareUsageStats,
            trailing: settingsToggle(
              key: kPrivacyStepUsageToggleKey,
              testId: 'onboarding-privacy-usage-toggle',
              value: settings.privacy.shareUsageStats,
              onChanged: (v) => _setUsageStatsConsent(ref, v),
            ),
          ),
          const SizedBox(height: WpSpacing.sm),
          SettingRow(
            testId: 'onboarding-privacy-crash-row',
            key: kPrivacyStepCrashToggleKey,
            icon: LucideIcons.shieldCheck,
            iconSize: WpIconSize.md,
            label: l10n.settingsErrorReporting,
            subtitle: l10n.settingsErrorReportingSubtitle,
            semanticToggledValue: settings.errorReporting,
            trailing: settingsToggle(
              testId: 'onboarding-privacy-crash-toggle',
              value: settings.errorReporting,
              onChanged: (v) => _setErrorReportingConsent(ref, v),
            ),
          ),
          const SizedBox(height: WpSpacing.md),
          Semantics(
            identifier: 'onboarding-privacy-settings-hint',
            child: Text(l10n.onboardingPrivacySettingsHint, style: muted),
          ),
          const SizedBox(height: WpSpacing.sm),
          Transform.translate(
            offset: const Offset(-kOnboardingGhostLinkInset, 0),
            child: WpButton(
              testId: 'onboarding-privacy-policy-link',
              label: l10n.aboutPrivacyPolicy,
              icon: LucideIcons.externalLink,
              variant: WpButtonVariant.ghost,
              tone: WpButtonTone.neutral,
              size: WpButtonSize.dense,
              onPressed: () => openExternalUrl(
                context,
                privacyPolicyUrl(Localizations.localeOf(context).languageCode),
              ),
            ),
          ),
          const SizedBox(height: WpSpacing.xl),
          SizedBox(
            width: kOnboardingCopyWidth,
            // loam-ignore: a11y-interactive-semantics – semantics provided in WpHeroButton.build
            child: WpHeroButton(
              testId: nextTestId,
              key: primaryKey,
              label: nextLabel ?? l10n.onboardingNext,
              onPressed: onNext,
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
    if (!value) _track(ref, 'share_usage_stats');
    ref
        .read(settingsProvider.notifier)
        .updateSettings((s) => s.copyWith(shareUsageStats: value));
    if (value) _track(ref, 'share_usage_stats');
  }

  /// Persists crash-reporting consent. Unlike usage stats, this toggle does
  /// not gate the telemetry channel that reports it, so there is no
  /// before/after ordering concern — mirrors [PrivacySection]'s
  /// `errorReporting` handler exactly.
  void _setErrorReportingConsent(WidgetRef ref, bool value) {
    CrashReporter.instance?.consentGranted = value;
    ref
        .read(settingsProvider.notifier)
        .updateSettings((s) => s.copyWith(errorReporting: value));
    _track(ref, 'error_reporting');
  }

  void _track(WidgetRef ref, String setting) {
    try {
      ref.read(telemetryProvider).trackSettingChange(setting);
    } catch (e) {
      _log.debug('telemetry failed: $e');
    }
  }
}

/// The closing painting's own layers: a faint vignette over the picture,
/// then the wave mark on top of it.
class _ClosingScene extends StatelessWidget {
  const _ClosingScene();

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      ClipRRect(
        borderRadius: WpRadius.borderXl,
        child: const DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              radius: 0.95,
              colors: [Colors.transparent, WpShadows.artVignette],
              stops: [0.62, 1],
            ),
          ),
        ),
      ),
      const _LogoMark(),
    ],
  );
}

/// The app's wave mark — the sound bars and the blue wave of the app icon,
/// without its tile and without the wordmark — large in the calm sky of the
/// closing painting (maintainer 2026-10-30), so the page ends on the brand.
/// It rises in once; with reduced motion it simply stands there. No shadow (§7:
/// shadows only for floating surfaces).
class _LogoMark extends StatelessWidget {
  const _LogoMark();

  static const _asset = 'assets/onboarding/privacy-logo-mark.webp';

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return Align(
      alignment: const AlignmentDirectional(-0.42, -0.3),
      child: FractionallySizedBox(
        heightFactor: 0.42,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: still ? 1 : 0, end: 1),
          duration: WpMotion.dramatic * 2,
          curve: Curves.easeOutCubic,
          builder: (context, t, child) => Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(0, 24 * (1 - t)),
              child: child,
            ),
          ),
          child: Image.asset(
            _asset,
            fit: BoxFit.contain,
            excludeFromSemantics: true,
          ),
        ),
      ),
    );
  }
}
