/// Navigation transition tests — A1 motion alignment for _AppShell.
///
/// Proves observable behaviour of the page-switching AnimatedSwitcher:
///   a) Slide offset stays within expected bounds during transition — no
///      bouncing (WpMotion.defaultCurve = Curves.easeOut has no overshoot).
///   b) With MediaQuery.disableAnimations = true, the transition is immediate:
///      the old page is removed from the widget tree after a single frame pair.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/tokens.dart';

import '../fixtures/test_helpers.dart';

// ---------------------------------------------------------------------------
// Minimal test harness — mirrors _AppShell's content AnimatedSwitcher exactly.
// Defined here (not in production code) to keep the test focused on behaviour,
// not structural implementation details.
// ---------------------------------------------------------------------------

class _PageSwitcherHarness extends StatefulWidget {
  const _PageSwitcherHarness({super.key});

  @override
  State<_PageSwitcherHarness> createState() => _PageSwitcherHarnessState();
}

class _PageSwitcherHarnessState extends State<_PageSwitcherHarness> {
  String _page = 'alpha';

  void navigate(String page) => setState(() => _page = page);

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: WpMotion.durationFor(context, WpMotion.normal),
      switchInCurve: WpMotion.defaultCurve,
      switchOutCurve: WpMotion.defaultCurve,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.0, 0.015),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: KeyedSubtree(
        key: ValueKey(_page),
        child: SizedBox.expand(child: Text(_page)),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('_AppShell page transition — A1 motion alignment', () {
    // -----------------------------------------------------------------------
    // a) No bouncing
    //
    // With WpMotion.defaultCurve (Curves.easeOut), the SlideTransition's
    // position.value.dy must stay within [-ε, 0.016] at every sampled frame.
    // An elastic/spring curve would push dy below 0 (overshoot past target).
    // -----------------------------------------------------------------------
    testWidgets(
      'a) slide offset stays within [-ε, 0.016] — no bouncing during A1 transition',
      (tester) async {
        final key = GlobalKey<_PageSwitcherHarnessState>();
        await tester.pumpWidget(makeTestable(_PageSwitcherHarness(key: key)));
        await tester.pump();

        // Navigate: triggers the AnimatedSwitcher transition
        key.currentState!.navigate('beta');

        // Sample every 10 ms across the full 200 ms (WpMotion.normal) window.
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 10));

          // During an active transition both incoming and outgoing children
          // each have a SlideTransition. Check all of them.
          final slides = tester.widgetList<SlideTransition>(
            find.byType(SlideTransition),
          );

          for (final slide in slides) {
            final dy = slide.position.value.dy;
            expect(
              dy,
              greaterThanOrEqualTo(-0.001),
              reason:
                  'Offset.dy must not go negative (no bouncing) at ${i * 10} ms',
            );
            expect(
              dy,
              lessThanOrEqualTo(0.016),
              reason:
                  'Offset.dy must not exceed begin value (0.015) at ${i * 10} ms',
            );
          }
        }

        await tester.pumpAndSettle();
        expect(find.text('beta'), findsOneWidget);
      },
    );

    // -----------------------------------------------------------------------
    // b) Reduced-motion: immediate transition
    //
    // WpMotion.durationFor returns Duration.zero when disableAnimations is
    // true. AnimatedSwitcher with duration=0 completes synchronously, so the
    // old page ('alpha') is removed from the widget tree after only two pumps
    // (one to process setState + start animation, one for cleanup).
    // -----------------------------------------------------------------------
    testWidgets(
      'b) with disableAnimations=true, old page is removed after two frames (immediate)',
      (tester) async {
        final key = GlobalKey<_PageSwitcherHarnessState>();

        // Build with disableAnimations=true embedded in the MediaQueryData.
        // Using a custom tree (not makeTestable) so we own the MediaQuery.
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(800, 600),
                disableAnimations: true,
              ),
              child: Scaffold(body: _PageSwitcherHarness(key: key)),
            ),
          ),
        );
        await tester.pump();

        expect(find.text('alpha'), findsOneWidget);
        expect(find.text('beta'), findsNothing);

        // Navigate
        key.currentState!.navigate('beta');
        // First pump: process setState + AnimationController.forward() → completes
        //             synchronously (duration=0) + schedules cleanup.
        await tester.pump();
        // Second pump: AnimatedSwitcher cleanup removes the old outgoing child.
        await tester.pump();

        // Old page is gone — animation was immediate
        expect(
          find.text('alpha'),
          findsNothing,
          reason:
              'Old page must be removed immediately when disableAnimations=true',
        );
        expect(find.text('beta'), findsOneWidget);
      },
    );
  });
}
