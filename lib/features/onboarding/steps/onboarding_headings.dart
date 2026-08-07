/// Shared heading vocabulary for onboarding pages 2–5.
///
/// The redesign's central structural fix: before it, page 5 stacked two
/// headline-sized bold titles while page 3 carried three same-sized block
/// titles and no page title at all — so no page had a visible hierarchy and
/// every page looked equally "full". There are now exactly two levels:
/// [OnboardingPageHeading] (one per page) and [OnboardingSectionLabel] (for
/// the blocks inside a page), separated by a clear size step (22 vs 14).
///
/// Both are start-aligned on [kSettingRowInset] — the horizontal padding
/// [SettingRow] applies to itself — so headings and the frameless settings
/// rows beneath them share one reading edge. `EdgeInsetsDirectional` keeps
/// that edge correct under RTL.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../settings/settings_widgets.dart' show kSettingRowInset;

/// One per page: the title the page is about, plus an optional explanatory
/// line. Mirrors the Conductor reference's start-aligned "Set up Conductor"
/// lockup (`.scratch/onboarding-redesign/reference-conductor/
/// SCR-20260804-kayx.png`).
class OnboardingPageHeading extends StatelessWidget {
  const OnboardingPageHeading({
    super.key,
    required this.title,
    this.subtitle,
    this.subtitleMaxWidth = 560,
  });

  final String title;
  final String? subtitle;

  /// Bounded measure for the explanatory line so it keeps a readable line
  /// length instead of running the full (deliberately wide) page frame.
  final double subtitleMaxWidth;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark
        ? WpColorsDark.textPrimary
        : WpColorsLight.textPrimary;
    final textSecondary = isDark
        ? WpColorsDark.textSecondary
        : WpColorsLight.textSecondary;

    return Padding(
      padding: const EdgeInsetsDirectional.only(start: kSettingRowInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            textAlign: TextAlign.start,
            style: TextStyle(
              fontSize: WpTypography.headline,
              fontWeight: FontWeight.bold,
              color: textPrimary,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: WpSpacing.xs),
            _MeasuredMaxWidth(
              maxWidth: subtitleMaxWidth,
              child: Text(
                subtitle!,
                textAlign: TextAlign.start,
                style: TextStyle(
                  fontSize: WpTypography.subheading,
                  color: textSecondary,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A width cap that also *measures* itself at that width.
///
/// [ConstrainedBox], which is what the subtitle used before, asks its child
/// for an intrinsic height at the width coming in from above and only then
/// applies its own cap — so as soon as the cap adds a wrapped line, the
/// reported height is short by exactly those lines. Nothing depended on that
/// measurement until the settings-shaped pages started dividing their
/// leftover height ([OnboardingPageFill]) among their blocks, which is done
/// from the intrinsic height: an under-reported heading became a page that
/// overflowed by two lines under an enlarged system text scale, and only
/// there.
///
/// Everything else matches [ConstrainedBox]: a subtitle narrower than
/// [maxWidth] keeps its own width, and a frame narrower than [maxWidth] (the
/// last page's two columns are ~390 px) simply wins.
class _MeasuredMaxWidth extends SingleChildRenderObjectWidget {
  const _MeasuredMaxWidth({
    required this.maxWidth,
    required Widget super.child,
  });

  final double maxWidth;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasuredMaxWidth(maxWidth);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderMeasuredMaxWidth renderObject,
  ) {
    renderObject.maxWidth = maxWidth;
  }
}

class _RenderMeasuredMaxWidth extends RenderProxyBox {
  _RenderMeasuredMaxWidth(this._maxWidth);

  double _maxWidth;
  set maxWidth(double value) {
    if (value == _maxWidth) return;
    _maxWidth = value;
    markNeedsLayout();
  }

  BoxConstraints _innerConstraints(BoxConstraints constraints) {
    final maxWidth = math.min(constraints.maxWidth, _maxWidth);
    return constraints.copyWith(
      minWidth: math.min(constraints.minWidth, maxWidth),
      maxWidth: maxWidth,
    );
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      math.min(super.computeMinIntrinsicWidth(height), _maxWidth);

  @override
  double computeMaxIntrinsicWidth(double height) =>
      math.min(super.computeMaxIntrinsicWidth(height), _maxWidth);

  @override
  double computeMinIntrinsicHeight(double width) =>
      super.computeMinIntrinsicHeight(math.min(width, _maxWidth));

  @override
  double computeMaxIntrinsicHeight(double width) =>
      super.computeMaxIntrinsicHeight(math.min(width, _maxWidth));

  @override
  Size computeDryLayout(BoxConstraints constraints) => child == null
      ? constraints.smallest
      : constraints.constrain(
          child!.getDryLayout(_innerConstraints(constraints)),
        );

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(_innerConstraints(constraints), parentUsesSize: true);
    size = constraints.constrain(child.size);
  }
}

/// A block inside a page. Deliberately a long way below
/// [OnboardingPageHeading] in weight so a page with several blocks still
/// reads as one page.
class OnboardingSectionLabel extends StatelessWidget {
  const OnboardingSectionLabel({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark
        ? WpColorsDark.textPrimary
        : WpColorsLight.textPrimary;
    final textMuted = isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;

    return Padding(
      padding: const EdgeInsetsDirectional.only(start: kSettingRowInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            textAlign: TextAlign.start,
            style: TextStyle(
              fontSize: WpTypography.subheading,
              fontWeight: FontWeight.w700,
              color: textPrimary,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              textAlign: TextAlign.start,
              style: TextStyle(
                fontSize: WpTypography.small,
                color: textMuted,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
