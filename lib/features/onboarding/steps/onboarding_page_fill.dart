/// Vertical rhythm of the onboarding pages: header top, body directly under
/// it, centred in the leftover height between header and footer.
///
/// The onboarding window is fixed at 1100×720, which leaves a 551-px content
/// viewport — more than most pages need. Anchoring a 247-px page to the top of
/// that viewport reads as "everything squeezed into the top third, dead space
/// below"; centring the *whole* page (header included) leaves it floating with
/// no stable reading start, and — the bug this construction exists to prevent
/// — makes the header land at a different height on every page, because its
/// position then depends on how tall the rest of the page happens to be.
///
/// So every page is exactly two parts — a header and a body — and
/// [OnboardingPage] is the one place that assembles them:
///
/// ```dart
/// OnboardingPage(
///   header: OnboardingPageHeading(title: ..., subtitle: ...),
///   body: const ModelStep(),
/// )
/// ```
///
/// [OnboardingPageFill] stretches the page to the height the viewport actually
/// offers, and [OnboardingPageBody] — which [OnboardingPage] wraps the body in
/// for you — centres the body in the leftover height. The header stays at the
/// top, the shell's navigation row stays at the bottom, and the gap between
/// header and body is [kOnboardingHeaderGap] on every page rather than
/// whatever a page's own height left there.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../core/theme/tokens.dart';
import '../../settings/settings_widgets.dart' show kSettingRowInset;
import 'onboarding_headings.dart';

/// The one gap between a page's header and its body.
///
/// Every page used to pick its own (`lg` on three pages, `xl` on one, `xxl` on
/// two), which is how the flow ended up with six different header rhythms for
/// one repeated composition. `xxl` is the value of the two pages designed last
/// (Welcome, Privacy) and the only one of the three that stays clearly above
/// the `lg`/`xl` gaps used *inside* a body — a header gap that measures the
/// same as the gap between two setting rows stops reading as a header gap.
///
/// Pages that fill the viewport pay nothing for the larger value: the extra
/// height comes out of the slack [OnboardingPageBody] would otherwise have
/// centred with. Only [OnboardingPage.headerGap] may deviate, and only with a
/// stated reason — see its one caller in `onboarding_overlay.dart`.
const double kOnboardingHeaderGap = WpSpacing.xxl;

/// Marks the header slot of an [OnboardingPage], so a test can measure the gap
/// beneath it without knowing which widget the page put there.
@visibleForTesting
const kOnboardingPageHeaderKey = Key('onboarding-page-header');

/// The explanatory line of a compacted page (see [OnboardingPage]), placed
/// below the body. Lets a test assert where the line sits.
@visibleForTesting
const kOnboardingCompactSubtitleKey = Key('onboarding-page-compact-subtitle');

/// One onboarding page: a fixed header, [kOnboardingHeaderGap] under it, and
/// everything else starting right there, with the leftover height trailing.
///
/// Seven of the eight pages are this and nothing else, so they say so rather
/// than each re-writing the same `Column`. The page owns the header and the
/// gap; the step widget owns only its own content, which is what keeps the
/// step widgets bare-mountable in their own tests.
///
/// The Start page is the same header over body, so it takes the same fill path.
class OnboardingPage extends StatelessWidget {
  const OnboardingPage({
    super.key,
    required this.header,
    required this.body,
    this.headerGap = kOnboardingHeaderGap,
  });

  /// The page's fixed reading start — an `OnboardingPageHeading` on every page
  /// but Welcome, whose brand lockup plays that role.
  final Widget header;

  /// Everything under the header, as ONE block starting exactly [headerGap]
  /// below it (see [OnboardingPageBody]) rather than distributed over
  /// hand-weighted gaps.
  final Widget body;

  /// Deviation from [kOnboardingHeaderGap]. Document the reason at the call
  /// site; there is currently exactly one (the hotkey page's confirmed-
  /// conflict branch, which has 13 px of slack in German and cannot afford
  /// the canonical gap).
  final double headerGap;

  @override
  Widget build(BuildContext context) {
    // At large text scale the header keeps its title only and the explanatory
    // line moves under the body (after the controls, still in the scroll
    // view). Same rule on every page, so the flow reads as one rhythm.
    var headerWidget = header;
    var bodyWidget = body;
    var gap = headerGap;
    final heading = header;
    if (heading is OnboardingPageHeading &&
        heading.subtitle != null &&
        onboardingCompactText(context)) {
      headerWidget = OnboardingPageHeading(
        title: heading.title,
        subtitleMaxWidth: heading.subtitleMaxWidth,
        testId: heading.testId,
      );
      bodyWidget = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          body,
          const SizedBox(height: WpSpacing.lg),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: kSettingRowInset),
            child: OnboardingSubtitleText(
              key: kOnboardingCompactSubtitleKey,
              text: heading.subtitle!,
              maxWidth: heading.subtitleMaxWidth,
            ),
          ),
        ],
      );
      // The canonical gap was sized for a subtitle line; a title alone reads
      // as a lockup at `lg`. Deviations keep their own value.
      if (gap == kOnboardingHeaderGap) gap = WpSpacing.lg;
    }
    // Keyed so the gap under the header is measurable without a test
    // having to know what kind of widget a given page put in the header
    // slot — page 1's is a brand lockup, every other page's is an
    // [OnboardingPageHeading]. See the header-gap guard in
    // `onboarding_overlay_test.dart`.
    final headerSlot = KeyedSubtree(
      key: kOnboardingPageHeaderKey,
      child: OnboardingHeadingFocus(child: headerWidget),
    );
    final availableHeight = OnboardingPageFill.availableHeightOf(context);
    if (availableHeight != null) {
      final budget = OnboardingFillBudget();
      // Inside the overlay the page measures its own natural height and fills
      // the viewport from there, so no child is ever squeezed into a slot it
      // cannot fit (see [OnboardingFillColumn]).
      return OnboardingFillColumn(
        availableHeight: availableHeight,
        gap: gap,
        budget: budget,
        children: [
          headerSlot,
          OnboardingPageBody(
            child: _OnboardingBudgetScope(budget: budget, child: bodyWidget),
          ),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        headerSlot,
        SizedBox(height: gap),
        OnboardingPageBody(child: bodyWidget),
      ],
    );
  }
}

/// Stretches [child] to [availableHeight] when the page is shorter than that,
/// and marks the subtree as the place where an [OnboardingPageBody] may grow.
///
/// Pages taller than [availableHeight] keep their natural height and scroll as
/// before: the page's height is `max(natural, availableHeight)`, so the fill
/// can only ever add space, never take any away. That property is what makes
/// it safe to apply to the tight pages too (the hotkey page's conflict branch
/// has 13 px of slack in German), and it keeps the no-scroll guard in
/// `onboarding_overlay_test.dart` meaningful — an overflowing page still
/// reports a scroll extent.
///
/// [OnboardingPage] does the measuring itself with [OnboardingFillColumn].
class OnboardingPageFill extends StatelessWidget {
  const OnboardingPageFill({
    super.key,
    required this.availableHeight,
    required this.child,
  });

  /// Height the page is offered — the scroll viewport minus its padding.
  final double availableHeight;

  final Widget child;

  /// The height the enclosing page is offered, or null outside a page (the
  /// step widgets are also mounted standalone in their own tests). Lets a step
  /// leave out a block that would not fit the viewport without scrolling.
  static double? availableHeightOf(BuildContext context) =>
      _OnboardingFillScope.availableHeightOf(context);

  @override
  Widget build(BuildContext context) {
    return _OnboardingFillScope(
      availableHeight: availableHeight,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: availableHeight),
        child: child,
      ),
    );
  }
}

/// Everything on a page that is not its header, starting directly under it and
/// letting whatever height is left over trail below.
///
/// One block per page, deliberately: dividing the leftover space between
/// several hand-weighted gaps let each page invent its own vertical rhythm,
/// and on page 1 it moved the header itself. Placing the body as a single
/// unit is the same mechanism — a flex child of the page column — with one
/// decision instead of four.
///
/// **Centred, always (2026-08-17) — and it used to be a per-page choice.**
/// The body was `Expanded(Align(topCenter))` by default, with sparse pages
/// opting into a plain top anchor. That gave the flow exactly two ways to
/// spend leftover height, both of them decided per page, and the distance
/// from the header's bottom edge to the first thing under it came out
/// anywhere between 20 px (Try & Go) and 117.5 px (Appearance) — a factor of
/// six, off a single shared header constant.
///
/// One rule replaces the choice: the body sits centred between header and
/// footer on every page. The known trade-off — the header-to-content gap
/// grows on content-sparse pages, up to ~245 px on the hotkey page before the
/// content work in tickets 03–06 landed — is accepted rather than fixed by
/// layout alone; it is the companion content tickets that keep it in check,
/// not this rule.
///
/// Outside an [OnboardingPageFill] — the page widgets are also mounted
/// standalone in their own tests, where the height is unbounded and a flex
/// child would assert — this collapses to the child itself, so a page with no
/// space to give keeps exactly the spacing it had.
class OnboardingPageBody extends StatelessWidget {
  const OnboardingPageBody({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _OnboardingFillScope.isFilling(context)
        ? Center(child: child)
        : child;
  }
}

class _OnboardingFillScope extends InheritedWidget {
  const _OnboardingFillScope({
    required this.availableHeight,
    required super.child,
  });

  final double availableHeight;

  static _OnboardingFillScope? _maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_OnboardingFillScope>();

  static bool isFilling(BuildContext context) => _maybeOf(context) != null;

  static double? availableHeightOf(BuildContext context) =>
      _maybeOf(context)?.availableHeight;

  @override
  bool updateShouldNotify(_OnboardingFillScope oldWidget) =>
      oldWidget.availableHeight != availableHeight;
}

/// Column of a fill page: the header at the top, the body centred in the
/// space between header and bottom, and never less than [availableHeight].
///
/// Measures both children at their natural height first, so the page is as
/// tall as its content when the content is taller than the viewport and
/// otherwise as tall as the viewport. The earlier version fitted the body into
/// an `Expanded` slot whose height came from [IntrinsicHeight], which
/// under-reports widgets such as `LayoutBuilder`; the body then overflowed. The
/// same under-report on the Start page gave the page a tight height that was
/// shorter than its content, so its link sat outside the scroll extent.
class OnboardingFillColumn extends MultiChildRenderObjectWidget {
  const OnboardingFillColumn({
    super.key,
    required this.availableHeight,
    required this.gap,
    this.budget,
    required super.children,
  });

  final OnboardingFillBudget? budget;

  final double availableHeight;
  final double gap;

  @override
  RenderOnboardingFillColumn createRenderObject(BuildContext context) =>
      RenderOnboardingFillColumn(
        availableHeight: availableHeight,
        gap: gap,
        budget: budget,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderOnboardingFillColumn renderObject,
  ) {
    if (renderObject.availableHeight == availableHeight &&
        renderObject.gap == gap &&
        renderObject.budget == budget) {
      return;
    }
    renderObject
      ..availableHeight = availableHeight
      ..gap = gap
      ..budget = budget
      ..markNeedsLayout();
  }
}

/// Render object of [OnboardingFillColumn]: child 0 is the header, child 1 the
/// body. Both get the full width; the body is laid out without a height limit.
class _FillColumnParentData extends ContainerBoxParentData<RenderBox> {}

class RenderOnboardingFillColumn extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _FillColumnParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _FillColumnParentData> {
  RenderOnboardingFillColumn({
    required this.availableHeight,
    required this.gap,
    this.budget,
  });

  /// Room left for a motion slot in the body; set from [OnboardingFillColumn].
  OnboardingFillBudget? budget;

  /// Set from [OnboardingFillColumn]; a change re-lays the page out.
  double availableHeight;

  /// The gap under the header, set from [OnboardingFillColumn].
  double gap;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _FillColumnParentData) {
      child.parentData = _FillColumnParentData();
    }
  }

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    final widthConstraints = BoxConstraints.tightFor(width: width);
    final header = firstChild;
    final body = header == null ? null : childAfter(header);

    var headerHeight = 0.0;
    if (header != null) {
      header.layout(widthConstraints, parentUsesSize: true);
      headerHeight = header.size.height;
    }
    // Published before the body is measured, so a motion slot inside the body
    // reads the room left for its clip during this same layout pass.
    budget?.publish(
      available: availableHeight,
      headerAndGap: headerHeight + gap,
    );
    var bodyHeight = 0.0;
    if (body != null) {
      body.layout(
        widthConstraints.copyWith(minHeight: 0, maxHeight: double.infinity),
        parentUsesSize: true,
      );
      bodyHeight = body.size.height;
    }

    final naturalHeight = headerHeight + gap + bodyHeight;
    size = constraints.constrain(
      Size(width, math.max(availableHeight, naturalHeight)),
    );

    final headerData = header?.parentData as _FillColumnParentData?;
    headerData?.offset = Offset.zero;
    if (body != null) {
      // The body fills the slot below the header exactly, as an `Expanded`
      // did: its own [OnboardingPageBody] centres the content inside it. The
      // slot always holds the content, since the page is at least
      // header + gap + natural body tall.
      // Only a minimum height, never a maximum: the content is then laid out
      // exactly as in the measuring pass (a page may size its content from its
      // constraints, and a tight height made it taller than the slot).
      final slotHeight = math.max(0.0, size.height - headerHeight - gap);
      body.layout(
        widthConstraints.copyWith(
          minHeight: slotHeight,
          maxHeight: double.infinity,
        ),
        parentUsesSize: true,
      );
      final bodyData = body.parentData as _FillColumnParentData;
      bodyData.offset = Offset(0, headerHeight + gap);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);
}

/// Height budget a fill page hands to a motion slot in its body.
///
/// The fill column publishes the viewport height and the header plus gap
/// during its layout, before it measures the body. A slot in the body reads
/// them in its own layout, so its clip gets only the room that is left after
/// the rest of the page. Pages without a slot never read it and lay out
/// exactly as before.
class OnboardingFillBudget {
  double available = 0;
  double headerAndGap = 0;

  /// Stores the values for the body measured right after. Never marks a
  /// descendant dirty: a parent must not mutate its children while it lays
  /// them out. A slot is rebuilt per page, and the values only change with
  /// the window, whose constraints re-lay the body out anyway.
  void publish({required double available, required double headerAndGap}) {
    this.available = available;
    this.headerAndGap = headerAndGap;
  }

  /// The budget of the nearest fill page, or `null` outside one (standalone
  /// widget tests of a step).
  static OnboardingFillBudget? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_OnboardingBudgetScope>()
      ?.budget;
}

class _OnboardingBudgetScope extends InheritedWidget {
  const _OnboardingBudgetScope({required this.budget, required super.child});

  final OnboardingFillBudget budget;

  @override
  bool updateShouldNotify(_OnboardingBudgetScope oldWidget) =>
      oldWidget.budget != budget;
}
