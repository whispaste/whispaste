library;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/l10n/generated/app_localizations.dart';
import '../core/theme/colors.dart';
import '../services/hardware_info_service.dart' as hw;
import '../services/model_download_service.dart';

/// Shared UI mapping for tier-safety warnings.
abstract final class TierSafetyPresentation {
  static String? message({
    required L10n l10n,
    required QualityTier tier,
    required TierSafety safety,
    required hw.GpuInfo? gpu,
  }) {
    if (gpu == null) return null;

    switch (safety) {
      case TierSafety.usable:
        return null;
      case TierSafety.slowWithoutGpu:
        return l10n.qualityTierWarningNoGpu;
      case TierSafety.vramRisky:
        if (gpu.vendor == hw.GpuVendor.nvidia) {
          return tier == QualityTier.premium
              ? l10n.qualityTierWarningNvidiaPremium
              : l10n.qualityTierWarningNvidiaBalanced;
        }
        if (gpu.vendor == hw.GpuVendor.apple && tier == QualityTier.premium) {
          return l10n.qualityTierWarningApplePremium;
        }
        return tier == QualityTier.premium
            ? l10n.qualityTierWarningIgpuPremium
            : l10n.qualityTierWarningIgpuBalanced;
      case TierSafety.vramCritical:
        if (gpu.vendor == hw.GpuVendor.apple) {
          return l10n.qualityTierWarningApplePremium;
        }
        return tier == QualityTier.premium
            ? l10n.qualityTierWarningIgpuPremium
            : l10n.qualityTierWarningIgpuBalanced;
    }
  }

  static Color color({required bool isDark, required TierSafety safety}) {
    switch (safety) {
      case TierSafety.usable:
        return isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
      case TierSafety.slowWithoutGpu:
        return isDark ? WpColorsDark.accent : WpColorsLight.accent;
      case TierSafety.vramRisky:
        return isDark ? WpColorsDark.warning : WpColorsLight.warning;
      case TierSafety.vramCritical:
        return isDark ? WpColorsDark.error : WpColorsLight.error;
    }
  }

  static IconData icon(TierSafety safety) {
    switch (safety) {
      case TierSafety.slowWithoutGpu:
        return LucideIcons.info;
      case TierSafety.vramRisky:
      case TierSafety.vramCritical:
        return LucideIcons.triangleAlert;
      case TierSafety.usable:
        return LucideIcons.info;
    }
  }
}
