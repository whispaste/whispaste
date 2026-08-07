/// Widget-level semantics tests for core reusable interactive widgets.
///
/// Verifies that central widgets expose accessible names via
/// `find.bySemanticsLabel(...)` so screen readers can announce them.
///
/// Scope: widgets addressed in issue 01-a11y-semantics-core and
/// issue 03-a11y-semantics-onboarding.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/widgets/markdown_toolbar.dart';
import 'package:whispaste/widgets/sidebar.dart';
import 'package:whispaste/widgets/wp_hero_button.dart';

import '../../fixtures/test_helpers.dart';

void main() {
  group('WpMarkdownToolbar — toolbar button semantics', () {
    late TextEditingController controller;
    late FocusNode focusNode;

    setUp(() {
      controller = TextEditingController();
      focusNode = FocusNode();
    });

    tearDown(() {
      controller.dispose();
      focusNode.dispose();
    });

    testWidgets('Bold button exposes semantics label', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          WpMarkdownToolbar(
            controller: controller,
            isDark: true,
            focusNode: focusNode,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel('Bold (Ctrl+B)'),
        findsOneWidget,
        reason:
            'Bold toolbar button must expose its tooltip as a semantics label',
      );
    });

    testWidgets('All toolbar buttons expose semantics labels', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          WpMarkdownToolbar(
            controller: controller,
            isDark: true,
            focusNode: focusNode,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The 7 buttons: Bold, Italic, Heading, Bullet list,
      // Numbered list, Quote, Code.
      for (final label in [
        'Bold (Ctrl+B)',
        'Italic (Ctrl+I)',
        'Heading',
        'Bullet list (Ctrl+Shift+L)',
        'Numbered list',
        'Quote',
        'Code',
      ]) {
        expect(
          find.bySemanticsLabel(label),
          findsOneWidget,
          reason: 'Toolbar button "$label" must expose a semantics label',
        );
      }
    });
  });

  group('WpSidebar — nav item semantics', () {
    testWidgets('Nav items expose their label as semantics', (tester) async {
      const items = [
        WpNavItem(id: 'history', icon: Icons.history, label: 'History'),
        WpNavItem(id: 'settings', icon: Icons.settings, label: 'Settings'),
      ];

      await tester.pumpWidget(
        makeTestable(
          WpSidebar(
            items: items,
            activeId: 'history',
            onItemTap: (_) {},
            bottomItems: const [],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel('History'),
        findsWidgets,
        reason: 'Nav item must expose its label for screen readers',
      );
    });
  });

  group('WpHeroButton — onboarding step button semantics', () {
    testWidgets('WpHeroButton is navigable via semantics for screen readers', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          WpHeroButton(
            label: 'Continue',
            gradient: const LinearGradient(colors: [Colors.orange, Colors.red]),
            onPressed: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // WpHeroButton wraps its content in Semantics(button: true, label:).
      // The label is propagated to the semantics tree via SemanticsNode.
      final button = find.byType(WpHeroButton);
      expect(button, findsOneWidget);

      final semantics = tester.getSemantics(button);
      expect(
        semantics.label,
        contains('Continue'),
        reason:
            'WpHeroButton must expose its label for screen readers — '
            'used throughout onboarding (issue 03-a11y-semantics-onboarding)',
      );
    });

    testWidgets('Disabled WpHeroButton still exposes semantics label', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          const WpHeroButton(
            label: 'Next',
            gradient: LinearGradient(colors: [Colors.blue, Colors.purple]),
            onPressed: null, // disabled
          ),
        ),
      );
      await tester.pumpAndSettle();

      final button = find.byType(WpHeroButton);
      expect(button, findsOneWidget);

      final semantics = tester.getSemantics(button);
      expect(
        semantics.label,
        contains('Next'),
        reason:
            'Disabled WpHeroButton must still expose its label so screen '
            'readers can announce it and its disabled state',
      );
    });
  });
}
