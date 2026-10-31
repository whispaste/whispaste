/// Shared heading vocabulary for the onboarding pages.
///
/// Every page has one [OnboardingPageHeading]: the title the page is about,
/// plus an optional explanatory line. It is start-aligned on
/// [kSettingRowInset] — the horizontal padding [SettingRow] applies to itself —
/// so the heading and the frameless settings rows beneath it share one reading
/// edge. `EdgeInsetsDirectional` keeps that edge correct under RTL.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../core/accessibility/announce.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/theme.dart';
import '../../../core/theme/tokens.dart';
import '../../settings/settings_widgets.dart' show kSettingRowInset;

/// One per page: the title the page is about, plus an optional explanatory
/// line. Mirrors the Conductor reference's start-aligned "Set up Conductor"
/// lockup (`internal-notes
/// SCR-20260804-kayx.png`).
class OnboardingPageHeading extends StatelessWidget {
  const OnboardingPageHeading({
    super.key,
    required this.title,
    this.subtitle,
    this.subtitleMaxWidth = 640,
    this.testId,
  });

  final String title;
  final String? subtitle;

  /// Stable identifier of the heading (`onboarding-<page>-heading`), so the
  /// guard tests and agents address the title without its localized text.
  final String? testId;

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
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: kSettingRowInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // A semantic heading: screen readers jump to it on a page change,
          // where the shell moves keyboard focus to the page.
          Semantics(
            header: true,
            identifier: testId,
            child: Text(
              title,
              textAlign: TextAlign.start,
              style: WpTextStyles.pageTitle,
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
            OnboardingSubtitleText(text: subtitle!, maxWidth: subtitleMaxWidth),
          ],
        ],
      ),
    );
  }
}

/// Text scale from which an onboarding page compacts itself: the header keeps
/// only its title, the explanatory line moves below the page's controls (see
/// `OnboardingPage`), and the motion clip is left out.
///
/// Measured 2026-10-26 on the hotkey page (`ux_small_window_test.dart`
/// probes): at 1.3 the mode row still sits inside both 1280x680 and 1024x600
/// unscrolled; at 2.0 it lies more than 200 px below the visible area while
/// the explanatory line stands above it. 1.6 is the first scale of the band
/// where the header alone starts to cost a controls-row of room.
const double kOnboardingCompactTextScale = 1.6;

/// Whether the enclosing page is at or above [kOnboardingCompactTextScale].
bool onboardingCompactText(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(1) >= kOnboardingCompactTextScale;

/// The explanatory line under a page title, start-aligned and width-capped.
/// Shared by [OnboardingPageHeading] and by a compacted page, which places it
/// below its controls instead.
class OnboardingSubtitleText extends StatelessWidget {
  const OnboardingSubtitleText({
    super.key,
    required this.text,
    this.maxWidth = 640,
  });

  final String text;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return _MeasuredMaxWidth(
      maxWidth: maxWidth,
      child: Text(
        text,
        textAlign: TextAlign.start,
        style: TextStyle(
          fontSize: WpTypography.subheading,
          color: WpColors.textSecondary,
          height: 1.5,
        ),
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

/// Debug label of the focus node that marks one onboarding page, so a
/// heading can tell this page's controls from the outgoing page's.
const kOnboardingPageFocusLabel = 'onboardingPage';

/// Marks the subtree of one onboarding page in the focus tree. It never takes
/// focus itself and is skipped by traversal.
class OnboardingPageFocusRoot extends StatelessWidget {
  const OnboardingPageFocusRoot({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Focus(
    debugLabel: kOnboardingPageFocusLabel,
    canRequestFocus: false,
    skipTraversal: true,
    child: child,
  );
}

/// Debug label of the focus node that marks a page's initial control.
const kOnboardingInitialFocusLabel = 'onboardingInitialFocus';

/// Gives focus to the control inside it when it appears, instead of the page
/// heading: the inline shortcut recorder must get the keystrokes without a
/// click. Flutter's `autofocus` cannot do this here, as it only applies
/// while nothing in the scope has focus, and the outgoing page's heading
/// still holds it during a page change. As the heading gets no focus, the
/// page is announced with [announcement] instead.
class OnboardingInitialFocus extends StatefulWidget {
  const OnboardingInitialFocus({
    super.key,
    required this.announcement,
    required this.child,
  });

  /// What a screen reader says when the control takes focus: the page's
  /// heading and what the control is for.
  final String announcement;
  final Widget child;

  @override
  State<OnboardingInitialFocus> createState() => _OnboardingInitialFocusState();
}

class _OnboardingInitialFocusState extends State<OnboardingInitialFocus> {
  final FocusNode _node = FocusNode(
    debugLabel: kOnboardingInitialFocusLabel,
    canRequestFocus: false,
    skipTraversal: true,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = _node.children.where((n) => n.canRequestFocus).firstOrNull;
      if (target == null) return;
      target.requestFocus();
      announce(
        View.of(context),
        widget.announcement,
        Directionality.of(context),
      );
    });
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Focus(focusNode: _node, child: widget.child);
}

/// Moves focus to the page header when the page appears, so the new page is
/// announced and Enter and Escape act on it right away (Onboarding v6, V07).
///
/// The overlay keys each page by its step, so a page change mounts a new
/// header and this runs once per page. Focus is a semantics focus too: the
/// `Focus` node carries the header's semantics, so a screen reader lands on
/// the title.
class OnboardingHeadingFocus extends StatefulWidget {
  const OnboardingHeadingFocus({super.key, required this.child});

  final Widget child;

  @override
  State<OnboardingHeadingFocus> createState() => _OnboardingHeadingFocusState();
}

class _OnboardingHeadingFocusState extends State<OnboardingHeadingFocus> {
  final FocusNode _node = FocusNode(debugLabel: 'onboardingHeading');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_pageHasInitialFocus()) {
        _node.requestFocus();
      }
    });
  }

  /// This page names its own first control ([OnboardingInitialFocus]).
  bool _pageHasInitialFocus() =>
      _page?.descendants.any(
        (n) => n.debugLabel == kOnboardingInitialFocusLabel,
      ) ??
      false;

  FocusNode? get _page => _node.ancestors
      .where((n) => n.debugLabel == kOnboardingPageFocusLabel)
      .firstOrNull;

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Focus(focusNode: _node, child: widget.child);
}
