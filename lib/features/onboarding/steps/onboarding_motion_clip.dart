import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import 'onboarding_headings.dart' show onboardingCompactText;
import 'onboarding_page_fill.dart' show OnboardingFillBudget;
import 'welcome_step.dart' show onboardingBeatAssetPath;

/// A pre-rendered HyperFrames beat shown on a step page other than Welcome.
///
/// Every clip is the static `_still_` frame of the theme variant of the active
/// app theme (hell, dunkel or marine). Maintainer decision 7b (2026-10-28):
/// the beats are stills, not animated WebP, so the page does not move and no
/// animation needs a reduced-motion path. The clip carries no text and is
/// decorative, so it is excluded from semantics; [testId] is the only handle
/// for tests.
///
/// The box keeps the 460:288 panel ratio of the Welcome showcase and never
/// grows wider than the page's content block (capped at
/// [kOnboardingMotionClipMaxWidth]), so a page body stays within the fixed
/// onboarding window.
///
/// A box the page budget leaves out arrives with 0x0 constraints. Then
/// nothing is built below it: no [Image] is created, so no still is decoded
/// for a clip nobody sees (UX-088). The visibility decision itself is made
/// where the budget is known, in [_RenderMotionSlot].
class OnboardingMotionClip extends StatelessWidget {
  const OnboardingMotionClip({
    super.key,
    required this.beat,
    required this.testId,
  });

  /// Beat number as rendered, 1-based (`m3-access` is beat 3).
  final int beat;

  final String testId;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: testId,
      excludeSemantics: true,
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: kOnboardingMotionClipMaxWidth,
          ),
          // Decided on the constraints the box is given: 0 wide or high means
          // the budget left it out, and then no image stream is started.
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth <= 0 || constraints.maxHeight <= 0) {
                return const SizedBox.shrink();
              }
              return AspectRatio(
                aspectRatio: kOnboardingMotionClipAspect,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: WpColors.floatingSurface,
                    borderRadius: WpRadius.borderLg,
                  ),
                  child: ClipRRect(
                    borderRadius: WpRadius.borderLg,
                    child: Image.asset(
                      onboardingBeatAssetPath(index: beat - 1),
                      width: double.infinity,
                      height: double.infinity,
                      fit: BoxFit.cover,
                      excludeFromSemantics: true,
                      // A missing variant leaves the calm surface behind it,
                      // which is the same empty stage the Welcome page shows.
                      errorBuilder: (context, error, stackTrace) =>
                          const SizedBox.expand(),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Width cap of a step clip: the reading measure of the onboarding body (640
/// px, `_readingMeasure` in `onboarding_overlay.dart`). The clip takes the
/// width of that content block, not a fixed 400 px, so on a wide window it
/// lines up with the controls under it (UX-092). Narrower pages get less.
const double kOnboardingMotionClipMaxWidth = 640;

/// Width-to-height ratio of every beat (460:288 panel, same as Welcome).
const double kOnboardingMotionClipAspect = 460 / 288;

/// Below this room a motion clip is left out entirely, with no still frame.
///
/// 96 px (150 px wide at the 460:288 ratio) is a judgement, not a measured
/// legibility limit: the old 120 left the German speech page at 800x716 with
/// no clip while the shorter Hebrew text kept one (UX-086). The clip is
/// decorative, so the smallest size that still reads as the beat is enough;
/// the UX-086 guard in `onboarding_flow_test.dart` pins that page at 800x716.
const double kOnboardingMotionClipMinHeight = 96;

/// A step body with its motion beat above it, the clip first and the step's
/// own content under it, separated by `lg`.
///
/// The clip takes only the room the page has left after its content and the
/// header (see [OnboardingFillBudget]). It keeps the 460:288 ratio, is never
/// wider than [kOnboardingMotionClipMaxWidth], and is left out when less than
/// [kOnboardingMotionClipMinHeight] remains. Outside a fill page there is no
/// budget, and the clip keeps its full size.
class OnboardingMotionStep extends StatelessWidget {
  const OnboardingMotionStep({
    super.key,
    required this.beat,
    required this.testId,
    required this.child,
  });

  final int beat;
  final String testId;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Deliberate (UX-087): at large text scale the clip is left out on every
    // step, not capped. It is decorative and excluded from semantics; the text
    // and controls keep the whole window. See [kOnboardingCompactTextScale].
    if (onboardingCompactText(context)) return child;
    return _OnboardingMotionSlot(
      budget: OnboardingFillBudget.maybeOf(context),
      textDirection: Directionality.of(context),
      children: [
        OnboardingMotionClip(beat: beat, testId: testId),
        child,
      ],
    );
  }
}

class _OnboardingMotionSlot extends MultiChildRenderObjectWidget {
  const _OnboardingMotionSlot({
    required this.budget,
    required this.textDirection,
    required super.children,
  });

  final OnboardingFillBudget? budget;
  final TextDirection textDirection;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMotionSlot(budget: budget, textDirection: textDirection);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderMotionSlot renderObject,
  ) {
    renderObject
      ..budget = budget
      ..textDirection = textDirection;
  }
}

/// Children: index 0 is the clip, index 1 the step content.
class _RenderMotionSlot extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _MotionSlotParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _MotionSlotParentData> {
  _RenderMotionSlot({required this._budget, required this._textDirection});

  OnboardingFillBudget? _budget;
  set budget(OnboardingFillBudget? value) {
    if (identical(value, _budget)) return;
    _budget = value;
    markNeedsLayout();
  }

  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (value == _textDirection) return;
    _textDirection = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _MotionSlotParentData) {
      child.parentData = _MotionSlotParentData();
    }
  }

  @override
  void performLayout() {
    final clip = firstChild!;
    final content = childAfter(clip)!;
    final width = constraints.maxWidth;

    content.layout(BoxConstraints.tightFor(width: width), parentUsesSize: true);
    final contentHeight = content.size.height;

    var clipWidth = math.min(kOnboardingMotionClipMaxWidth, width);
    var clipHeight = clipWidth / kOnboardingMotionClipAspect;
    var showClip = true;
    final budget = _budget;
    if (budget != null) {
      final room =
          budget.available - budget.headerAndGap - contentHeight - WpSpacing.lg;
      showClip = room >= kOnboardingMotionClipMinHeight;
      if (showClip && room < clipHeight) {
        clipHeight = room;
        clipWidth = clipHeight * kOnboardingMotionClipAspect;
      }
    }

    if (showClip) {
      clip.layout(
        BoxConstraints.tightFor(width: clipWidth, height: clipHeight),
      );
    } else {
      clip.layout(const BoxConstraints.tightFor(width: 0, height: 0));
      clipWidth = 0;
      clipHeight = 0;
    }
    final band = showClip ? clipHeight + WpSpacing.lg : 0.0;

    final clipX = _textDirection == TextDirection.ltr ? 0.0 : width - clipWidth;
    (clip.parentData! as _MotionSlotParentData).offset = Offset(clipX, 0);
    (content.parentData! as _MotionSlotParentData).offset = Offset(0, band);
    size = constraints.constrain(Size(width, band + contentHeight));
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);
}

class _MotionSlotParentData extends ContainerBoxParentData<RenderBox> {}
