/// Onboarding-time Smart Mode discovery touchpoint —
/// `.scratch/smart-mode-v2/issues/08-onboarding-touchpoints.md`.
///
/// Shown, at most once, right as a first-run user finishes onboarding (the
/// [OnboardingStepId.tryAndGo] step's "Start Using" action) — a skippable
/// interstitial rather than a new fixed step, so [OnboardingStepId] and the
/// step-index persistence it drives stay untouched. Never shown during a
/// manual review or an onboarding revision run: both re-enter onboarding on
/// an app that is already fully set up, so introducing a still-optional
/// feature there would be a re-pitch, not a discovery moment.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/generated/app_localizations.dart';
import '../../core/theme/tokens.dart';
import '../../services/smart_mode/smart_mode_model_download_service.dart';
import '../../widgets/dialog.dart';
import '../../widgets/wp_button.dart';
import '../settings/sections/smart_mode_section.dart'
    show startSmartModeDownloadWithRamCheck;

/// Shows the one-time Smart Mode intro dialog. Resolves once the user either
/// starts the download or skips — both are "seen", so the caller does not
/// need to branch on the result to know whether to show it again.
Future<void> showSmartModeOnboardingHint(
  BuildContext context,
  WidgetRef ref,
) async {
  final l10n = L10n.of(context);
  await showWpDialog<void>(
    context: context,
    title: l10n.smartModeOnboardingHintTitle,
    content: Text(l10n.smartModeOnboardingHintBody),
    actions: [
      WpButton(
        label: l10n.smartModeOnboardingHintSkipCta,
        variant: WpButtonVariant.ghost,
        tone: WpButtonTone.neutral,
        onPressed: () => Navigator.of(context).pop(),
      ),
      const SizedBox(width: WpSpacing.sm),
      WpButton(
        label: l10n.smartModeOnboardingHintDownloadCta,
        variant: WpButtonVariant.primary,
        onPressed: () {
          final notifier = ref.read(smartModeDownloadProvider.notifier);
          Navigator.of(context).pop();
          unawaited(
            startSmartModeDownloadWithRamCheck(
              context: context,
              notifier: notifier,
              l10n: l10n,
            ),
          );
        },
      ),
    ],
  );
}
