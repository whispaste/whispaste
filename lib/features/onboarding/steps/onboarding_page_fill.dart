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
/// So every page is exactly two parts:
///
/// ```dart
/// Column(children: [
///   OnboardingPageHeading(...),          // fixed, same y on every page
///   SizedBox(height: WpSpacing.lg),      // the minimum gap under it
///   OnboardingPageBody(child: ...),      // everything else, centred as one
/// ])
/// ```
///
/// [OnboardingPageFill] stretches the page to the height the viewport actually
/// offers, and [OnboardingPageBody] takes the leftover height and centres the
/// body inside it. The header stays at the top, the shell's navigation row
/// stays at the bottom, and only the space around the body breathes.
library;

import 'package:flutter/material.dart';

/// Stretches [child] to [availableHeight] when the page is shorter than that,
/// and marks the subtree as the place where an [OnboardingPageBody] may grow.
///
/// Pages taller than [availableHeight] keep their natural height and scroll as
/// before: [IntrinsicHeight] resolves to `max(natural, availableHeight)`, so
/// the fill can only ever add space, never take any away. That property is
/// what makes it safe to apply to the tight pages too (the hotkey page's
/// conflict branch has 12 px of slack in German), and it keeps the no-scroll
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
  const OnboardingPageBody({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _OnboardingFillScope.isFilling(context)
        ? Expanded(child: Center(child: child))
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
