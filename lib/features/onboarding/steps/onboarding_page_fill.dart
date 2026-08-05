/// Vertical space distribution for the settings-shaped onboarding pages.
///
/// The onboarding window is fixed at 1100×720, which leaves a 551-px content
/// viewport — more than most pages need. Anchoring a 247-px page to the top
/// of that viewport (what the flow did before) reads as "everything squeezed
/// into the top third, dead space below"; centring it (what it did before
/// that) leaves the page floating with no stable reading start. Both are the
/// same mistake: the page is laid out as if it did not know how much room it
/// has.
///
/// [OnboardingPageFill] hands the page that knowledge. It stretches its child
/// to the height the viewport actually offers, and [OnboardingFlexGap] — the
/// growing half of a gap between two blocks — divides the leftover space
/// between the gaps by weight, instead of letting it pile up at the bottom.
/// The heading stays fixed at the top and the shell's navigation row stays
/// fixed at the bottom; only what lies between them breathes.
library;

import 'package:flutter/material.dart';

/// Stretches [child] to [availableHeight] when the page is shorter than that,
/// and marks the subtree as the place where [OnboardingFlexGap]s may grow.
///
/// Pages taller than [availableHeight] keep their natural height and scroll as
/// before: [IntrinsicHeight] resolves to `max(natural, availableHeight)`, so
/// the fill can only ever add space, never take any away. That property is
/// what makes it safe to apply to the tight pages too (page 3 has 27 px of
/// slack in Hebrew), and it keeps the no-scroll guard in
/// `onboarding_overlay_test.dart` meaningful — an overflowing page still
/// reports a scroll extent.
///
/// [OnboardingFlexGap] contributes zero intrinsic height, so the intrinsic
/// measurement [IntrinsicHeight] takes is exactly the page's natural,
/// minimum-gap height.
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

/// The growing half of a gap between two blocks of an onboarding page.
///
/// Always sits next to the fixed [SizedBox] that carries the gap's minimum,
/// so a page that has no space to give keeps exactly the spacing it had:
/// outside an [OnboardingPageFill] — the page widgets are also mounted
/// standalone in their own tests — this collapses to nothing.
///
/// [flex] weights this gap against the page's other gaps. Every page ends on
/// one of these: without a trailing gap the last block would sit 20 px above
/// the Back/Next row.
class OnboardingFlexGap extends StatelessWidget {
  const OnboardingFlexGap({super.key, this.flex = 1});

  final int flex;

  @override
  Widget build(BuildContext context) {
    return _OnboardingFillScope.isFilling(context)
        ? Spacer(flex: flex)
        : const SizedBox.shrink();
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
