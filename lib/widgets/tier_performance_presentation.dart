library;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/l10n/generated/app_localizations.dart';
import '../core/theme/colors.dart';
import '../services/model_download_service.dart';

/// Shared UI mapping for tier-performance info messages.
///
/// The message line is graded by [TierPerformance] so the user can see, at a
/// glance, what a tier will cost on *their* hardware — the app's
/// hardware-inclusivity promise is worth little if every verdict is painted
/// the same reassuring blue. The grading is deliberately shallow (see
/// [color]): it flags a time cost, never a defect.
abstract final class WpTierPerformancePresentation {
  /// Returns an informational message about tier performance, or null if none needed.
  static String? message({
    required L10n l10n,
    required QualityTier tier,
    required TierPerformance performance,
    double? rtf,
    Map<QualityTier, double>? benchmarkRtf,
  }) {
    switch (performance) {
      case TierPerformance.fast:
        return null; // No message for fast tiers - they're expected to work well
      case TierPerformance.moderate:
        return l10n.qualityTierInfoModerate;
      case TierPerformance.slow:
        // Show comparison vs compact tier if we have benchmark data
        if (rtf != null && rtf > 0 && benchmarkRtf != null) {
          final compactRtf = benchmarkRtf[QualityTier.compact];
          if (compactRtf != null && compactRtf > 0) {
            final ratio = (rtf / compactRtf).toStringAsFixed(1);
            return l10n.qualityTierInfoSlowerThanCompact(ratio);
          }
          // Fallback: just show the tier's own RTF
          return l10n.qualityTierInfoSlow(rtf.toStringAsFixed(1));
        }
        return l10n.qualityTierInfoSlow('2.0'); // Default fallback
      case TierPerformance.unmeasured:
        return l10n.qualityTierInfoBenchmarking;
    }
  }

  /// Color for the info line of [performance].
  ///
  /// Three steps, not four — and the omitted step is the amber one, for two
  /// independent reasons:
  ///
  /// 1. **The copy for `moderate` is praise.** `qualityTierInfoModerate` reads
  ///    "Good balance of speed and quality". An amber line under an affirmative
  ///    sentence tells the user two opposite things at once, so `moderate`
  ///    keeps the neutral accent: something worth reading, nothing worth
  ///    worrying about.
  /// 2. **Light-theme amber is not legible here.** This line renders at
  ///    `WpTypography.micro` (10 px) — normal text under WCAG 1.4.3, so it owes
  ///    4.5:1. `WpColorsLight.warning` reaches at most 3.11:1 on the settings
  ///    gradient and 2.76:1 on the accent-tinted selected row. It cannot carry
  ///    this text at any size used here. (`WpColorsLight.success` fails the
  ///    same floor at 3.74:1, which is why a green "fine" step is absent too.)
  ///
  /// What remains is honest and readable:
  ///
  /// | tier         | color       | says                                  |
  /// |--------------|-------------|---------------------------------------|
  /// | `fast`       | accent      | nothing — [message] returns null       |
  /// | `moderate`   | accent      | informational, no cost worth flagging  |
  /// | `slow`       | `error`     | this tier will visibly cost you time   |
  /// | `unmeasured` | `textMuted` | no verdict yet — don't imply one       |
  ///
  /// `error` on `slow` is a *cost* signal, not a fault signal; the paired icon
  /// is an hourglass rather than a warning triangle precisely so the line reads
  /// "slower on your machine", not "broken". `unmeasured` trades a little
  /// contrast (accent 5.02:1 → textMuted 4.42:1 at the worst gradient stop) for
  /// not dressing an unmeasured tier in the same confident blue as a measured
  /// one.
  static Color color({
    required bool isDark,
    required TierPerformance performance,
  }) {
    return switch (performance) {
      TierPerformance.fast || TierPerformance.moderate =>
        isDark ? WpColorsDark.accent : WpColorsLight.accent,
      TierPerformance.slow => isDark ? WpColorsDark.error : WpColorsLight.error,
      TierPerformance.unmeasured =>
        isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted,
    };
  }

  /// Icon for the info line of [performance] — see [color] for the pairing.
  ///
  /// All three are quiet metaphors: a gauge for a measured balance, an
  /// hourglass for time spent, an `info` glyph while there is nothing to
  /// report yet. No alert triangle — the slow tier is a trade-off the user
  /// chose, not a malfunction.
  static IconData icon(TierPerformance performance) {
    return switch (performance) {
      TierPerformance.fast || TierPerformance.moderate => LucideIcons.gauge,
      TierPerformance.slow => LucideIcons.hourglass,
      TierPerformance.unmeasured => LucideIcons.info,
    };
  }
}
