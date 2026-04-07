import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/widgets/section.dart';

import '../fixtures/test_helpers.dart';

void main() {
  group('WpSection (non-collapsible)', () {
    testWidgets('renders with title', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const WpSection(
            title: 'Audio Settings',
            child: Text('Content goes here'),
          ),
        ),
      );

      expect(find.text('Audio Settings'), findsOneWidget);
    });

    testWidgets('shows child content', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const WpSection(
            title: 'Audio Settings',
            child: Text('Microphone: Default'),
          ),
        ),
      );

      expect(find.text('Microphone: Default'), findsOneWidget);
    });

    testWidgets('shows optional subtitle', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const WpSection(
            title: 'Audio Settings',
            subtitle: 'Configure input devices',
            child: Text('Content'),
          ),
        ),
      );

      expect(find.text('Configure input devices'), findsOneWidget);
    });

    testWidgets('renders trailing widget', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          WpSection(
            title: 'Section',
            trailing: IconButton(
              icon: const Icon(Icons.add),
              onPressed: () {},
            ),
            child: const Text('Content'),
          ),
        ),
      );

      expect(find.byIcon(Icons.add), findsOneWidget);
    });
  });

  group('WpSection (collapsible)', () {
    testWidgets('initially expanded shows child content', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const WpSection(
            title: 'Advanced',
            collapsible: true,
            initiallyExpanded: true,
            child: Text('Advanced content'),
          ),
        ),
      );

      expect(find.text('Advanced'), findsOneWidget);
      expect(find.text('Advanced content'), findsOneWidget);
    });

    testWidgets('initially collapsed hides child content', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const WpSection(
            title: 'Advanced',
            collapsible: true,
            initiallyExpanded: false,
            child: Text('Advanced content'),
          ),
        ),
      );

      expect(find.text('Advanced'), findsOneWidget);
      // Content is in the tree but rendered with zero height via ClipRect
      // and heightFactor 0 — so it is not visible. We check the Align
      // widget's heightFactor.
      final align = tester.widget<Align>(find.byType(Align).last);
      expect(align.heightFactor, 0.0);
    });

    testWidgets('tapping header toggles collapsed state', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const WpSection(
            title: 'Advanced',
            collapsible: true,
            initiallyExpanded: false,
            child: Text('Visible now'),
          ),
        ),
      );

      // Tap the header to expand
      await tester.tap(find.text('Advanced'));
      await tester.pumpAndSettle();

      // After expanding, the Align heightFactor should be 1.0
      final align = tester.widget<Align>(find.byType(Align).last);
      expect(align.heightFactor, 1.0);
    });
  });
}
