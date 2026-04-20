library;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/l10n/generated/app_localizations.dart';
import '../core/theme/colors.dart';
import '../services/model_download_service.dart';

/// Shared UI mapping for tier-performance info messages.
/// All messages use neutral blue (accent) styling - no red/yellow warnings.
abstract final class TierPerformancePresentation {
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

  /// Returns the accent color (blue) for all performance tiers.
  /// All tier info uses neutral blue styling - no red/yellow warnings.
  static Color color({required bool isDark}) {
    return isDark ? WpColorsDark.accent : WpColorsLight.accent;
  }

  /// Always returns info icon - no warning triangles.
  static IconData icon(TierPerformance performance) {
    // Always use info icon for all performance levels
    return LucideIcons.info;
  }

  /// Returns a descriptive label for the performance level.
  static String performanceLabel(TierPerformance performance, L10n l10n) {
    switch (performance) {
      case TierPerformance.fast:
        return 'Fast';
      case TierPerformance.moderate:
        return 'Moderate';
      case TierPerformance.slow:
        return 'Slower';
      case TierPerformance.unmeasured:
        return 'Unknown';
    }
  }
}
