/// The frame is painted **once**, and none of the three bars that stand on it
/// paints a ground of its own.
///
/// The app frame — title bar, nav rail, status bar — is one continuous
/// diagonal ambient (`frameGradient`), applied at exactly one place: the
/// single `DecoratedBox` that is the first child of the root `Stack` in
/// `lib/app.dart`. That reading only survives if the bars standing on it stay
/// transparent: a flat fill on one of them cuts a visible seam across a
/// gradient that is supposed to read as one light source, no matter how quiet
/// the fill is. (That is why the nav rail's decorative chrome wash was dropped
/// in Ticket 06 — see *The Decorative Color Rule* in `lib/DESIGN.md`.)
///
/// The check is deliberately scoped to a bar's **own** ground: a painted box
/// that covers the bar edge-to-edge. Chips, pills, badges and hover states
/// legitimately carry fills — they are objects on the ground, not the ground —
/// and an assertion that forbade every fill in the subtree would be weakened
/// until it asserted nothing.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:whispaste/widgets/sidebar.dart';
import 'package:whispaste/widgets/status_bar.dart';
import 'package:whispaste/widgets/title_bar.dart';

import '../fixtures/test_helpers.dart';

/// Every widget kind that can put an opaque or translucent fill on screen
/// without a child asking for it. `Container`/`AnimatedContainer` are covered
/// by [DecoratedBox]: that is what they build into.
bool _isPaintCandidate(Widget w) =>
    w is DecoratedBox || w is ColoredBox || w is Material;

/// Whether [w] actually puts color down (a border alone is not a ground).
bool _paintsFill(Widget w) {
  if (w is DecoratedBox) {
    final decoration = w.decoration;
    if (decoration is BoxDecoration) {
      if (decoration.gradient != null) return true;
      final color = decoration.color;
      return color != null && color.a > 0;
    }
    // Any other decoration type (ShapeDecoration, …) paints something.
    return true;
  }
  if (w is ColoredBox) return w.color.a > 0;
  if (w is Material) {
    return w.type != MaterialType.transparency && (w.color?.a ?? 0) > 0;
  }
  return false;
}

/// Every fill inside [bar] that spans the bar edge-to-edge, i.e. every ground
/// the bar paints for itself.
List<String> _ownGrounds(WidgetTester tester, Finder bar) {
  final barSize = tester.getSize(bar);
  final offenders = <String>[];
  for (final element
      in find
          .descendant(
            of: bar,
            matching: find.byWidgetPredicate(_isPaintCandidate),
          )
          .evaluate()) {
    final widget = element.widget;
    if (!_paintsFill(widget)) continue;
    final renderObject = element.renderObject;
    if (renderObject is! RenderBox || !renderObject.hasSize) continue;
    final size = renderObject.size;
    if ((size.width - barSize.width).abs() < 0.5 &&
        (size.height - barSize.height).abs() < 0.5) {
      offenders.add('${widget.runtimeType} at $size');
    }
  }
  return offenders;
}

/// Asserts that nothing inside [bar] paints a fill spanning the whole bar.
///
/// Deliberately *not* guarded by "the subtree contains at least one paint
/// candidate": the macOS title bar legitimately contains none at all, so such
/// a guard would fail on a bar that is exactly as clean as it must be. What
/// proves the sweep is not vacuous is the planted-ground self-test below.
void _expectNoOwnGround(WidgetTester tester, Finder bar, String name) {
  expect(
    tester.getSize(bar).isEmpty,
    isFalse,
    reason: '$name rendered at zero size — nothing was measured',
  );
  expect(
    _ownGrounds(tester, bar),
    isEmpty,
    reason:
        '$name paints its own ground. The frame is painted once, in the '
        'single DecoratedBox at the root of app.dart; a fill spanning a whole '
        'bar reads as a seam in an ambient that must read as one light source '
        'across all three bars.',
  );
}

/// A bar that *does* paint its own ground, in each of the three ways a widget
/// can — the self-test for [_ownGrounds].
class _PlantedGround extends StatelessWidget {
  const _PlantedGround({required this.ground});

  final Widget Function(Widget child) ground;

  @override
  Widget build(BuildContext context) =>
      SizedBox(width: 72, height: 200, child: ground(const SizedBox.expand()));
}

void main() {
  const navItems = [
    WpNavItem(id: 'history', icon: LucideIcons.clock, label: 'History'),
    WpNavItem(id: 'about', icon: LucideIcons.info, label: 'About'),
  ];

  group('No bar paints its own ground', () {
    for (final brightness in [Brightness.dark, Brightness.light]) {
      final themeName = brightness == Brightness.dark ? 'dark' : 'light';

      testWidgets('$themeName: nav rail', (tester) async {
        await tester.pumpWidget(
          makeTestable(
            WpSidebar(items: navItems, activeId: 'history', onItemTap: (_) {}),
            brightness: brightness,
          ),
        );
        _expectNoOwnGround(tester, find.byType(WpSidebar), 'WpSidebar');
      });

      // Whichever branch the host platform takes (`_MacOSTitleBar` on macOS,
      // the window-controls layout elsewhere) — neither may carry a ground,
      // and the one that runs here is the one this test measures.
      testWidgets('$themeName: title bar', (tester) async {
        await tester.pumpWidget(
          makeTestable(const WpTitleBar(), brightness: brightness),
        );
        _expectNoOwnGround(tester, find.byType(WpTitleBar), 'WpTitleBar');
      });

      testWidgets('$themeName: status bar', (tester) async {
        await tester.pumpWidget(
          makeTestable(
            const WpStatusBar(sttModeLabel: 'Local', hotkeyLabel: 'Ctrl+Alt+D'),
            brightness: brightness,
          ),
        );
        await tester.pumpAndSettle();
        _expectNoOwnGround(tester, find.byType(WpStatusBar), 'WpStatusBar');
      });
    }
  });

  group('The sweep catches a ground that is there', () {
    final plants = <String, Widget Function(Widget)>{
      'DecoratedBox(color)': (child) => DecoratedBox(
        decoration: const BoxDecoration(color: Color(0x0DDA8BC8)),
        child: child,
      ),
      'DecoratedBox(gradient)': (child) => DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF000000), Color(0xFFFFFFFF)],
          ),
        ),
        child: child,
      ),
      'ColoredBox': (child) =>
          ColoredBox(color: const Color(0x11FFFFFF), child: child),
      'Material(color)': (child) => Material(
        type: MaterialType.canvas,
        color: const Color(0xFF123456),
        child: child,
      ),
    };

    plants.forEach((name, ground) {
      testWidgets(name, (tester) async {
        await tester.pumpWidget(makeTestable(_PlantedGround(ground: ground)));
        expect(
          _ownGrounds(tester, find.byType(_PlantedGround)),
          isNotEmpty,
          reason:
              'a $name spanning the whole bar went undetected — the sweep '
              'above would pass whatever the real bars painted',
        );
      });
    });
  });
}
