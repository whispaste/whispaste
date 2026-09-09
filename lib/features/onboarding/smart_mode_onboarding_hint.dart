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
///
/// The dialog's body leads with a static before/after example
/// ([_SmartModeExample]) rather than pure prose (ticket 14,
/// `.scratch/smart-mode-v2/issues/14-onboarding-example.md`): a first-run
/// user has never seen Smart Mode run, so showing the actual transformation
/// — filler words gone, punctuation and capitalization restored, same
/// wording and language — makes the payoff concrete instead of asking the
/// user to picture it from a feature description. The pair is hardcoded and
/// purely illustrative, never derived from anything the user dictated, and
/// mirrors exactly what [smartModeCleanupSystemPrompt] does (the preset a
/// user with Smart Mode still `off` would land on): fillers removed,
/// punctuation/capitalization fixed, content and language unchanged — not
/// the shortening or translation the other two presets perform.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/generated/app_localizations.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../services/smart_mode/smart_mode_model_download_service.dart';
import '../../widgets/dialog.dart';
import '../../widgets/wp_button.dart';
import '../settings/sections/smart_mode_section.dart'
    show startSmartModeDownloadWithRamCheck;

/// Locates the before/after example card in tests (e.g. the golden test) —
/// `_SmartModeExample` itself is private, so a [Key] is the only hook a test
/// in another library has to find it.
const Key smartModeOnboardingHintExampleKey = Key(
  'smart-mode-onboarding-hint-example',
);

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
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.smartModeOnboardingHintBody),
        const SizedBox(height: WpSpacing.md),
        _SmartModeExample(key: smartModeOnboardingHintExampleKey, l10n: l10n),
      ],
    ),
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

/// Static before/after example pair — see the library doc above for why the
/// dialog leads with this instead of pure prose.
///
/// Purely visual, no state: both text blocks are hardcoded, translated
/// [l10n] strings, never anything from the user's own dictation.
class _SmartModeExample extends StatelessWidget {
  const _SmartModeExample({super.key, required this.l10n});

  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(WpSpacing.sm),
      decoration: BoxDecoration(
        color: WpColors.surfaceVariant,
        borderRadius: WpRadius.borderMd,
        border: Border.all(color: WpColors.borderSubtle),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ExampleRow(
            label: l10n.smartModeOnboardingHintExampleBeforeLabel,
            text: l10n.smartModeOnboardingHintExampleBefore,
          ),
          const SizedBox(height: WpSpacing.sm),
          _ExampleRow(
            label: l10n.smartModeOnboardingHintExampleAfterLabel,
            text: l10n.smartModeOnboardingHintExampleAfter,
            emphasized: true,
          ),
        ],
      ),
    );
  }
}

class _ExampleRow extends StatelessWidget {
  const _ExampleRow({
    required this.label,
    required this.text,
    this.emphasized = false,
  });

  final String label;
  final String text;

  /// `true` for the "after" row — rendered in the default text color rather
  /// than [WpColors.textMuted], so the cleaned-up result reads as the payoff
  /// against the greyed-out raw dictation above it.
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: WpColors.textMuted,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: WpSpacing.xxs),
        Text(
          text,
          style: TextStyle(
            fontStyle: FontStyle.italic,
            color: emphasized ? null : WpColors.textMuted,
          ),
        ),
      ],
    );
  }
}
