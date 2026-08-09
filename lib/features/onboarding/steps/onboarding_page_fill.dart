/// Vertical rhythm of the onboarding pages: header top, body centred, footer
/// bottom.
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
/// for you — takes the leftover height and centres the body inside it. The
/// header stays at the top, the shell's navigation row stays at the bottom,
/// and only the space around the body breathes.
library;

import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';

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

/// One onboarding page: a fixed header, [kOnboardingHeaderGap] under it, and
/// everything else centred in the height that is left.
///
/// Six of the seven pages are this and nothing else, so they say so rather
/// than each re-writing the same `Column`. The page owns the header and the
/// gap; the step widget owns only its own content, which is what keeps the
/// step widgets bare-mountable in their own tests.
///
/// The exception is `OnboardingStepId.tryAndGo`, which is not a header over a
/// body but two side-by-side columns of unequal height — see `_fillsViewport`
/// in `onboarding_overlay.dart`.
class OnboardingPage extends StatelessWidget {
  const OnboardingPage({
    super.key,
    required this.header,
    required this.body,
    this.headerGap = kOnboardingHeaderGap,
    this.bodyAlignment = Alignment.center,
  });

  /// The page's fixed reading start — an `OnboardingPageHeading` on every page
  /// but Welcome, whose brand lockup plays that role.
  final Widget header;

  /// Everything under the header, centred as ONE block in the leftover height
  /// (see [OnboardingPageBody]) rather than distributed over hand-weighted
  /// gaps.
  final Widget body;

  /// Deviation from [kOnboardingHeaderGap]. Document the reason at the call
  /// site; there is currently exactly one (the hotkey page's confirmed-
  /// conflict branch, which has 13 px of slack in German and cannot afford
  /// the canonical gap).
  final double headerGap;

  /// Where [body] sits in the leftover height. Centred by default.
  ///
  /// [Alignment.topCenter] is for the *sparse* pages, and it exists because
  /// centring cannot be tuned out of them: the body is `Expanded(Center(...))`,
  /// so the leftover height is split into equal voids above and below it, and
  /// growing the body only ever reclaims half of what it adds from each side.
  /// On a page whose content comes to 226 px in a 551 px viewport that leaves
  /// ~160 px between the heading and the first thing it introduces — the
  /// heading reads as orphaned, and no amount of internal spacing reaches it.
  ///
  /// Top-aligning is not "the same fix applied harder": it moves the whole
  /// slack to the bottom, where trailing space under a short settings page is
  /// ordinary, instead of splitting it around the one gap that has to stay
  /// small. Opt-in per page rather than flipped globally, because the pages
  /// that fill or nearly fill the viewport (Welcome, Model, Appearance,
  /// Try & Go) have little slack to place and are unaffected either way — and
  /// leaving them on the default keeps their layout, and the measured heights
  /// in `onboarding_overlay_test.dart`, identical by construction.
  final AlignmentGeometry bodyAlignment;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        SizedBox(height: headerGap),
        OnboardingPageBody(alignment: bodyAlignment, child: body),
      ],
    );
  }
}

/// Stretches [child] to [availableHeight] when the page is shorter than that,
/// and marks the subtree as the place where an [OnboardingPageBody] may grow.
///
/// Pages taller than [availableHeight] keep their natural height and scroll as
/// before: [IntrinsicHeight] resolves to `max(natural, availableHeight)`, so
/// the fill can only ever add space, never take any away. That property is
/// what makes it safe to apply to the tight pages too (the hotkey page's
/// conflict branch has 13 px of slack in German), and it keeps the no-scroll
/// guard in `onboarding_overlay_test.dart` meaningful — an overflowing page
/// still reports a scroll extent.
///
/// [OnboardingPageBody] reports its own child's intrinsic height and nothing
/// more, so the measurement [IntrinsicHeight] takes is exactly the page's
/// natural, minimum-gap height.
class OnboardingPageFill extends StatelessWidget {
  const OnboardingPageFill({
    super.key,
    required this.availableHeight,
    required this.child,
  });

  /// Height the page is offered — the scroll viewport minus its padding.
  final double availableHeight;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _OnboardingFillScope(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: availableHeight),
        child: IntrinsicHeight(child: child),
      ),
    );
  }
}

/// Everything on a page that is not its header, centred in whatever height is
/// left between the header and the shell's navigation row.
///
/// One block per page, deliberately: dividing the leftover space between
/// several hand-weighted gaps let each page invent its own vertical rhythm,
/// and on page 1 it moved the header itself. Centring the body as a single
/// unit is the same mechanism — a flex child of the page column — with one
/// decision instead of four.
///
/// Outside an [OnboardingPageFill] — the page widgets are also mounted
/// standalone in their own tests, where the height is unbounded and a flex
/// child would assert — this collapses to the child itself, so a page with no
/// space to give keeps exactly the spacing it had.
class OnboardingPageBody extends StatelessWidget {
  const OnboardingPageBody({
    super.key,
    required this.child,
    this.alignment = Alignment.center,
  });

  final Widget child;

  /// See [OnboardingPage.bodyAlignment]. The default is the identity case:
  /// `Align(alignment: Alignment.center)` is what [Center] is, so every page
  /// that does not pass this renders exactly as before.
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return _OnboardingFillScope.isFilling(context)
        ? Expanded(
            child: Align(alignment: alignment, child: child),
          )
        : child;
  }
}

class _OnboardingFillScope extends InheritedWidget {
  const _OnboardingFillScope({required super.child});

  static bool isFilling(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_OnboardingFillScope>() !=
      null;

  @override
  bool updateShouldNotify(_OnboardingFillScope oldWidget) => false;
}
