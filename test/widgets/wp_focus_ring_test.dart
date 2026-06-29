/// Tests for WpFocusRing primitive and keyboard-focus-visible ring integration.
///
/// AC1 — keyboard focus → ring visible
/// AC2 — pointer tap  → ring NOT visible
/// AC3 — ring colour = accent token; ring is layout-neutral
/// AC4 — disableAnimations → Duration.zero via WpMotion.durationFor
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/theme/tokens.dart';
import 'package:whispaste/widgets/section.dart';
import 'package:whispaste/widgets/sidebar.dart';
import 'package:whispaste/widgets/wp_accent_button.dart';
import 'package:whispaste/widgets/wp_focus_ring.dart';

import '../fixtures/test_helpers.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Pumps a few short frames to settle focus without open-ended streams.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Returns the [CustomPaint] widget created by a [WpFocusRing].
CustomPaint _ringPaint(WidgetTester tester, Finder ringFinder) {
  return tester.widget<CustomPaint>(
    find.descendant(of: ringFinder, matching: find.byType(CustomPaint)).first,
  );
}

bool _ringVisible(WidgetTester tester, Finder ringFinder) =>
    _ringPaint(tester, ringFinder).foregroundPainter != null;

// ---------------------------------------------------------------------------
// Part 1 — WpFocusRing primitive (standalone mode)
// ---------------------------------------------------------------------------

void main() {
  group('WpFocusRing primitive — standalone mode', () {
    testWidgets('AC1 — ring shows when keyboard strategy is traditional', (
      tester,
    ) async {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(
        () => FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic,
      );

      await tester.pumpWidget(
        makeTestable(
          const Column(
            children: [
              // Autofocus anchor — Tab from here reaches WpFocusRing.
              Focus(autofocus: true, child: SizedBox.shrink()),
              WpFocusRing(child: SizedBox(width: 100, height: 48)),
            ],
          ),
        ),
      );
      await _settle(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await _settle(tester);

      final rings = find.byType(WpFocusRing);
      expect(
        rings,
        findsOneWidget,
        reason: 'WpFocusRing should be in the tree',
      );
      expect(
        _ringVisible(tester, rings),
        isTrue,
        reason: 'AC1: ring should appear on keyboard focus',
      );
    });

    testWidgets('AC2 — ring hidden when highlight strategy is touch', (
      tester,
    ) async {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTouch;
      addTearDown(
        () => FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic,
      );

      await tester.pumpWidget(
        makeTestable(
          const Column(
            children: [
              Focus(autofocus: true, child: SizedBox.shrink()),
              WpFocusRing(child: SizedBox(width: 100, height: 48)),
            ],
          ),
        ),
      );
      await _settle(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await _settle(tester);

      final rings = find.byType(WpFocusRing);
      expect(
        _ringVisible(tester, rings),
        isFalse,
        reason: 'AC2: ring must stay hidden in touch highlight mode',
      );
    });

    testWidgets('AC3 — ring colour matches theme accent token', (tester) async {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(
        () => FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic,
      );

      await tester.pumpWidget(
        makeTestable(
          const Column(
            children: [
              Focus(autofocus: true, child: SizedBox.shrink()),
              WpFocusRing(child: SizedBox(width: 100, height: 48)),
            ],
          ),
        ),
      );
      await _settle(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await _settle(tester);

      final ringFinder = find.byType(WpFocusRing);
      final paint = _ringPaint(tester, ringFinder);
      final accent = Theme.of(tester.element(ringFinder)).colorScheme.primary;

      expect(
        paint.foregroundPainter,
        isA<WpFocusRingPainter>(),
        reason: 'Painter should be a WpFocusRingPainter',
      );
      expect(
        (paint.foregroundPainter! as WpFocusRingPainter).color,
        accent,
        reason: 'AC3: ring colour must equal theme accent token',
      );
    });

    testWidgets('AC3 — ring is layout-neutral (widget size unchanged)', (
      tester,
    ) async {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(
        () => FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic,
      );

      await tester.pumpWidget(
        makeTestable(
          const Column(
            children: [
              Focus(autofocus: true, child: SizedBox.shrink()),
              WpFocusRing(child: SizedBox(width: 100, height: 48)),
            ],
          ),
        ),
      );
      await _settle(tester);

      final sizeBeforeFocus = tester.getSize(find.byType(WpFocusRing));

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await _settle(tester);

      final sizeAfterFocus = tester.getSize(find.byType(WpFocusRing));

      expect(
        sizeAfterFocus,
        sizeBeforeFocus,
        reason: 'AC3: ring must not shift layout — widget size unchanged',
      );
    });

    testWidgets(
      'AC4 — WpMotion.durationFor returns Duration.zero with disableAnimations',
      (tester) async {
        Duration? result;

        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(disableAnimations: true),
              child: Builder(
                builder: (ctx) {
                  result = WpMotion.durationFor(ctx, WpMotion.smooth);
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );

        expect(
          result,
          Duration.zero,
          reason:
              'AC4: WpMotion.durationFor must return zero when disableAnimations',
        );
      },
    );

    testWidgets(
      'AC4 — WpMotion.durationFor preserves duration when animations enabled',
      (tester) async {
        Duration? result;

        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(disableAnimations: false),
              child: Builder(
                builder: (ctx) {
                  result = WpMotion.durationFor(ctx, WpMotion.smooth);
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );

        expect(
          result,
          WpMotion.smooth,
          reason:
              'durationFor should return the original duration when animations are enabled',
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Part 2 — WpAccentButton integration
  // ---------------------------------------------------------------------------

  group('WpAccentButton focus ring', () {
    testWidgets('AC1 — shows ring on keyboard focus', (tester) async {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(
        () => FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic,
      );

      await tester.pumpWidget(
        makeTestable(
          Column(
            children: [
              const Focus(autofocus: true, child: SizedBox.shrink()),
              WpAccentButton(
                label: 'Test',
                gradient: const LinearGradient(
                  colors: [Color(0xFF3CCBE6), Color(0xFF0A99B8)],
                ),
                onPressed: () {},
              ),
            ],
          ),
        ),
      );
      await _settle(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await _settle(tester);

      final rings = find.byType(WpFocusRing);
      expect(
        rings,
        findsOneWidget,
        reason: 'WpAccentButton should contain WpFocusRing',
      );
      expect(
        _ringVisible(tester, rings),
        isTrue,
        reason: 'AC1: WpAccentButton ring should appear on keyboard focus',
      );
    });

    testWidgets('AC2 — ring hidden in touch mode', (tester) async {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTouch;
      addTearDown(
        () => FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic,
      );

      await tester.pumpWidget(
        makeTestable(
          Column(
            children: [
              const Focus(autofocus: true, child: SizedBox.shrink()),
              WpAccentButton(
                label: 'Test',
                gradient: const LinearGradient(
                  colors: [Color(0xFF3CCBE6), Color(0xFF0A99B8)],
                ),
                onPressed: () {},
              ),
            ],
          ),
        ),
      );
      await _settle(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await _settle(tester);

      final rings = find.byType(WpFocusRing);
      expect(
        _ringVisible(tester, rings),
        isFalse,
        reason: 'AC2: WpAccentButton ring must stay hidden in touch mode',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Part 2 — WpSection collapsible header
  // ---------------------------------------------------------------------------

  group('WpSection collapsible focus ring', () {
    testWidgets('AC1 — collapsible header shows ring on keyboard focus', (
      tester,
    ) async {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(
        () => FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic,
      );

      await tester.pumpWidget(
        makeTestable(
          const Column(
            children: [
              Focus(autofocus: true, child: SizedBox.shrink()),
              WpSection(
                title: 'Advanced',
                collapsible: true,
                child: Text('content'),
              ),
            ],
          ),
        ),
      );
      await _settle(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await _settle(tester);

      final rings = find.byType(WpFocusRing);
      expect(
        rings,
        findsWidgets,
        reason: 'Collapsible WpSection should have WpFocusRing',
      );

      final anyRingVisible = rings.evaluate().any((el) {
        final cp = find.descendant(
          of: find.byElementPredicate((e) => e == el),
          matching: find.byType(CustomPaint),
        );
        if (cp.evaluate().isEmpty) return false;
        return tester.widget<CustomPaint>(cp.first).foregroundPainter != null;
      });

      expect(
        anyRingVisible,
        isTrue,
        reason: 'AC1: collapsible section header ring should appear on focus',
      );
    });

    testWidgets('AC2 — collapsible header ring hidden in touch mode', (
      tester,
    ) async {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTouch;
      addTearDown(
        () => FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic,
      );

      await tester.pumpWidget(
        makeTestable(
          const Column(
            children: [
              Focus(autofocus: true, child: SizedBox.shrink()),
              WpSection(
                title: 'Advanced',
                collapsible: true,
                child: Text('content'),
              ),
            ],
          ),
        ),
      );
      await _settle(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await _settle(tester);

      final rings = find.byType(WpFocusRing);
      final anyRingVisible = rings.evaluate().any((el) {
        final cp = find.descendant(
          of: find.byElementPredicate((e) => e == el),
          matching: find.byType(CustomPaint),
        );
        if (cp.evaluate().isEmpty) return false;
        return tester.widget<CustomPaint>(cp.first).foregroundPainter != null;
      });

      expect(
        anyRingVisible,
        isFalse,
        reason:
            'AC2: collapsible section header ring must be hidden in touch mode',
      );
    });

    testWidgets(
      'AC4 — collapsible section collapse settles in one pump with disableAnimations',
      (tester) async {
        await tester.pumpWidget(
          makeTestable(
            // Inner MediaQuery overrides disableAnimations — nearest ancestor wins.
            const MediaQuery(
              data: MediaQueryData(
                size: Size(1280, 800),
                disableAnimations: true,
              ),
              child: WpSection(
                title: 'Advanced',
                collapsible: true,
                initiallyExpanded: true,
                child: Text('Advanced content'),
              ),
            ),
          ),
        );
        await tester.pump();

        // Collapse the section.
        await tester.tap(find.text('Advanced'));
        await tester
            .pump(); // single pump — should be enough with zero duration

        // With Duration.zero the animation completes in one frame.
        final align = tester.widget<Align>(find.byType(Align).last);
        expect(
          align.heightFactor,
          lessThan(0.5),
          reason:
              'AC4: collapse should complete in one pump with reduced motion',
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Part 2 — WpSidebar item focus ring
  // ---------------------------------------------------------------------------

  group('WpSidebar item focus ring', () {
    final items = [
      const WpNavItem(id: 'home', icon: LucideIcons.house, label: 'Home'),
      const WpNavItem(
        id: 'settings',
        icon: LucideIcons.settings,
        label: 'Settings',
      ),
    ];

    testWidgets('AC1 — sidebar nav item shows ring on keyboard focus', (
      tester,
    ) async {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(
        () => FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic,
      );

      await tester.pumpWidget(
        makeTestable(
          Row(
            children: [
              const Focus(autofocus: true, child: SizedBox.shrink()),
              WpSidebar(items: items, activeId: 'home', onItemTap: (_) {}),
            ],
          ),
        ),
      );
      await _settle(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await _settle(tester);

      final sidebarFinder = find.byType(WpSidebar);
      final ringsInSidebar = find.descendant(
        of: sidebarFinder,
        matching: find.byType(WpFocusRing),
      );
      expect(
        ringsInSidebar,
        findsWidgets,
        reason: 'Sidebar should contain WpFocusRing widgets',
      );

      final anyRingVisible = ringsInSidebar.evaluate().any((el) {
        final cp = find.descendant(
          of: find.byElementPredicate((e) => e == el),
          matching: find.byType(CustomPaint),
        );
        if (cp.evaluate().isEmpty) return false;
        return tester.widget<CustomPaint>(cp.first).foregroundPainter != null;
      });

      expect(
        anyRingVisible,
        isTrue,
        reason: 'AC1: focused sidebar nav item should show focus ring',
      );
    });

    testWidgets('AC2 — sidebar nav item ring hidden in touch mode', (
      tester,
    ) async {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTouch;
      addTearDown(
        () => FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic,
      );

      await tester.pumpWidget(
        makeTestable(
          Row(
            children: [
              const Focus(autofocus: true, child: SizedBox.shrink()),
              WpSidebar(items: items, activeId: 'home', onItemTap: (_) {}),
            ],
          ),
        ),
      );
      await _settle(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await _settle(tester);

      final sidebarFinder = find.byType(WpSidebar);
      final ringsInSidebar = find.descendant(
        of: sidebarFinder,
        matching: find.byType(WpFocusRing),
      );

      final anyRingVisible = ringsInSidebar.evaluate().any((el) {
        final cp = find.descendant(
          of: find.byElementPredicate((e) => e == el),
          matching: find.byType(CustomPaint),
        );
        if (cp.evaluate().isEmpty) return false;
        return tester.widget<CustomPaint>(cp.first).foregroundPainter != null;
      });

      expect(
        anyRingVisible,
        isFalse,
        reason: 'AC2: sidebar ring must stay hidden in touch mode',
      );
    });
  });
}
