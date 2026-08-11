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

  /// Color for the info line of [performance] — one hue at rising weight.
  ///
  /// **A neutral ramp, not a traffic light.** This is the design question the
  /// grading opened, and it is answered against warning colors. The line
  /// reports *how much time* a tier costs on this machine; a quantity gets one
  /// hue at several weights, never several hues (*The Categorical vs.
  /// Sequential Rule*, the same rule the analytics duration ramp follows). Three
  /// hues would make the line a verdict and turn a trade-off the user chose into
  /// a malfunction. That continues, rather than drops, the stance the
  /// predecessor comment held — "all tier info uses neutral blue styling, no
  /// red/yellow warnings": what changes is that the line is graded at all, not
  /// that it started warning. The flat blue went because it said nothing about
  /// the user's own hardware, which is the whole point of measuring; the amber
  /// and green it refused stay refused.
  ///
  /// The refusal is now also measurable rather than only principled. The line
  /// renders at `WpTypography.micro` (10 px) — normal text under WCAG 1.4.3, so
  /// it owes 4.5:1. `WpColorsLight.warning` reaches at most 3.11:1 on these
  /// grounds and `WpColorsLight.success` 3.74:1: a traffic light is not
  /// renderable here at AA at any size this line uses, whatever one thinks of
  /// it.
  ///
  /// **Which end is which.** Weight rises with the cost reported, so `slow`
  /// takes the ramp's far rung and `fast` its near one. Fading the line out as
  /// the tier gets slower would spend the most ink on the message that carries
  /// the least ("good balance of speed and quality") and the least on the one
  /// the user actually has to act on.
  ///
  /// | tier         | color         | says                                  |
  /// |--------------|---------------|---------------------------------------|
  /// | `fast`       | rung 2 (near) | nothing — [message] returns null      |
  /// | `moderate`   | rung 3        | worth reading, no cost worth weighing |
  /// | `slow`       | rung 4 (far)  | this tier will visibly cost you time  |
  /// | `unmeasured` | `textMuted`   | no verdict yet — off the ramp         |
  ///
  /// **`unmeasured` is not a rung.** A tier nobody has benchmarked has no
  /// position on an ordinal scale, so it may not occupy one — the same argument
  /// [WpCategorySlot.neutral] makes for not being a ninth category. It keeps
  /// `textMuted`: quieter than every rung and visibly off the hue.
  ///
  /// **What is actually on screen.** The line renders for the *current* tier
  /// only, so at most one rung is ever visible at a time, and the `fast` rung
  /// never is — [message] returns null there. Color carries nothing on its own:
  /// the message says the verdict in words and the paired [icon] repeats it, an
  /// hourglass for time spent rather than an alert triangle.
  static Color color({
    required bool isDark,
    required TierPerformance performance,
  }) {
    final rungs = _tierRampSlot.ramp(_tierRampTextRung + 3, isDark);
    return switch (performance) {
      TierPerformance.fast => rungs[_tierRampTextRung],
      TierPerformance.moderate => rungs[_tierRampTextRung + 1],
      TierPerformance.slow => rungs[_tierRampTextRung + 2],
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

/// The slot [WpTierPerformancePresentation.color] cuts its ramp from.
///
/// Named here rather than mixed at the call site for the reason every category
/// color is: a hue reached through a name is a statement about the data, a hue
/// written into a widget is decoration. Why `orchid` out of the nine:
///
/// * **Not the accent.** Ticket 11 answered ② with (b) — cyan belongs to the
///   brand voice alone, so no ordinal ramp may be built from it. `azure` is the
///   near miss and falls to the same argument once measured: 38° from the dark
///   accent and 32° from the light one, inside the 45° this app treats as
///   "mistakable for the one voice", and its rungs are pale desaturated
///   periwinkle sitting *in* the accent-washed selected row — which is exactly
///   where a column of graded blues starts reading as a disabled control.
/// * **The hue carries no verdict.** `ember` and `plum` border error red,
///   `brass` borders warning amber, `fern` and `moss` sit on the success band;
///   each would say "fault" about a tier that merely takes longer. 296°
///   magenta-violet means nothing else in this app.
/// * **`iris` is spoken for** — it is the analytics duration ramp's source
///   (Ticket 14), and one hue should not carry two ordinal scales.
/// * **Its 18° to Quartz is not a collision**, and the governance says so
///   directly: the decorative hue is held apart by form and weight rather than
///   hue distance, appearing only as a ≤5 % wash at 1.03–1.07:1 — under the
///   threshold at which a field has a readable hue at all. Opaque text at
///   ≥4.5:1 cannot be confused with it, even on the settings page the wash
///   covers.
///
/// The one property `iris` has that no second ramp can have: *no model wears
/// it*. `_modelSlots` spends seven of the eight category slots, so there is no
/// unworn slot left to take. `orchid` is `whisper-large-v3-turbo`'s bar hue —
/// one page away in Analytics, the only file that calls [categorySlotForModel];
/// nothing on the settings page paints a category at all.
const _tierRampSlot = WpCategorySlot.orchid;

/// The ramp's first rung that is legible as *text*, i.e. how many of its low
/// rungs this line skips.
///
/// [WpCategorySlot.ramp] is solved for a graphical object's 3:1 floor and its
/// low rungs sit near it. Against the accent-washed selected row this line
/// renders in, light rung 0 reaches 3.60:1 and rung 1 4.40:1 — both under the
/// 4.5:1 that 10 px normal text owes. So the text ramp is the ramp's top three
/// rungs; the two beneath it are object rungs, not text rungs, and skipping
/// them is cheaper than re-solving the palette for one line.
const _tierRampTextRung = 2;
