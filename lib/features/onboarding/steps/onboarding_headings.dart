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
    this.subtitleMaxWidth = 640,
  });

  final String title;
  final String? subtitle;

  /// Bounded measure for the explanatory line so it keeps a readable line
  /// length instead of running the full (deliberately wide) page frame.
  ///
  /// 640, matching `_readingMeasure` in `onboarding_overlay.dart`: this was
  /// 560 against a 720-px body, which is how every settings-shaped page came
  /// to end its heading 148 px short of where its own content ended. The head
  /// and the body under it are one column and now say so. 640 is still a
  /// bounded measure — the point of the cap was never the exact number but
  /// that a subtitle must not run the full width of a wide page — and no
  /// subtitle in any of the three locales gains a line at it.
  final double subtitleMaxWidth;

  @override
  Widget build(BuildContext context) {
    const textPrimary = WpColors.textPrimary;
    const textSecondary = WpColors.textSecondary;

    return Padding(
      padding: const EdgeInsetsDirectional.only(start: kSettingRowInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            textAlign: TextAlign.start,
            style: const TextStyle(
              fontSize: WpTypography.headline,
              fontWeight: FontWeight.bold,
              color: textPrimary,
            ),
          ),
          if (subtitle != null) ...[
            // `sm` (12), not `xs` (8): the smallest gaps in the flow were
            // picked as ratios and then used at their absolute size, and 8 px
            // under a 22-px title is not "tight, belongs together" — it is the
            // subtitle sitting on the title's descenders. The relationship the
            // 8 encoded (clearly below the 32-px header gap, so the lockup
            // stays one unit) survives at 12 with room to spare.
            const SizedBox(height: WpSpacing.sm),
            _MeasuredMaxWidth(
              maxWidth: subtitleMaxWidth,
              child: Text(
                subtitle!,
                textAlign: TextAlign.start,
                style: const TextStyle(
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
    const textPrimary = WpColors.textPrimary;
    const textMuted = WpColors.textMuted;

    return Padding(
      padding: const EdgeInsetsDirectional.only(start: kSettingRowInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // `heading` (16), not `subheading` (14). This label heads a whole
          // column — on Try & Go it introduces the entire quick-start — and at
          // 14 px it was the same size as the body text underneath it, so the
          // column read as a footnote to the page rather than as its second
          // half. 16 gives it a rank of its own without making it a second
          // page title: the page heading is 22 px, so the ladder now steps
          // 22 → 16 → 14 instead of jumping 22 → 14 → 14.
          Text(
            title,
            textAlign: TextAlign.start,
            style: const TextStyle(
              fontSize: WpTypography.heading,
              fontWeight: FontWeight.w700,
              color: textPrimary,
            ),
          ),
          if (subtitle != null) ...[
            // `xxs`, not the hardcoded 2 px this used to be: the only raw
            // pixel value in the file, and the one gap in the flow that could
            // not be reasoned about in token steps.
            const SizedBox(height: WpSpacing.xxs),
            Text(
              subtitle!,
              textAlign: TextAlign.start,
              style: const TextStyle(
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
