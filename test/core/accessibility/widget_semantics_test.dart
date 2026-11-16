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
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/widgets/markdown_toolbar.dart';
import 'package:whispaste/widgets/sidebar.dart';
import 'package:whispaste/widgets/wp_hero_button.dart';

import '../../fixtures/test_helpers.dart';

void main() {
  group('WpMarkdownToolbar — toolbar button semantics', () {
    late TextEditingController controller;
    late FocusNode focusNode;
    late L10n l10n;

    setUpAll(() async {
      l10n = await L10n.delegate.load(const Locale('en'));
    });

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
          WpMarkdownToolbar(controller: controller, focusNode: focusNode),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel(
          l10n.markdownToolbarBold(
            WpMarkdownFormatting.boldShortcutLabel(l10n),
          ),
        ),
        findsOneWidget,
        reason:
            'Bold toolbar button must expose its tooltip as a semantics label',
      );
    });

    testWidgets('All toolbar buttons expose semantics labels', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          WpMarkdownToolbar(controller: controller, focusNode: focusNode),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      // The 9 buttons: Bold, Italic, Heading, Bullet list, Numbered list,
      // Checklist, Quote, Code, and — behind a divider — Find and replace.
      // Labels out of the ARB files (Ticket 27), each with its shortcut, each
      // with a stable identifier and a 48 dp target (#652). Whenever the
      // toolbar grows a button, it belongs in this list: the test's name
      // promises *all* of them.
      final buttons = <String, String>{
        'bold': l10n.markdownToolbarBold(
          WpMarkdownFormatting.boldShortcutLabel(l10n),
        ),
        'italic': l10n.markdownToolbarItalic(
          WpMarkdownFormatting.italicShortcutLabel(l10n),
        ),
        'heading': l10n.markdownToolbarHeading(
          WpMarkdownFormatting.headingShortcutLabel(l10n),
        ),
        'bullet-list': l10n.markdownToolbarBulletList(
          WpMarkdownFormatting.bulletListShortcutLabel(l10n),
        ),
        'numbered-list': l10n.markdownToolbarNumberedList(
          WpMarkdownFormatting.numberedListShortcutLabel(l10n),
        ),
        'checklist': l10n.markdownToolbarChecklist(
          WpMarkdownFormatting.checklistShortcutLabel(l10n),
        ),
        'quote': l10n.markdownToolbarQuote(
          WpMarkdownFormatting.quoteShortcutLabel(l10n),
        ),
        'code': l10n.markdownToolbarCode(
          WpMarkdownFormatting.codeShortcutLabel(l10n),
        ),
        'find': l10n.findReplaceToggle,
      };
      expect(find.bySemanticsLabel(l10n.markdownToolbarGroup), findsOneWidget);
      for (final MapEntry(key: id, value: label) in buttons.entries) {
        final byId = find.bySemanticsIdentifier('editor-toolbar-$id');
        expect(byId, findsOneWidget, reason: 'no identifier for "$id"');
        expect(
          find.bySemanticsLabel(label),
          findsOneWidget,
          reason: 'Toolbar button "$label" must expose a semantics label',
        );
        final size = tester.getSize(byId);
        expect(
          size.width >= 48 && size.height >= 48,
          isTrue,
          reason: '"$id" is $size, below the 48 dp target',
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
        makeTestable(WpHeroButton(label: 'Continue', onPressed: () {})),
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
