import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/features/settings/settings_widgets.dart';
import 'package:whispaste/widgets/section.dart';

import '../fixtures/test_helpers.dart';

void main() {
  // The section head sits directly above the settings rows, so its title has
  // to start where their content starts. Before this was pinned the title sat
  // at 15 and the row icons at 12 — near enough to read as a mistake, far
  // enough to see. The number lives in section.dart (a shared widget must not
  // import a feature constant), so it can only be kept honest from here.
  group('WpSection shares the settings reading edge', () {
    testWidgets('title text starts at kSettingRowInset, like the row icon', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          const WpSection(
            title: 'Audio',
            padding: EdgeInsets.zero,
            child: SettingRow(
              icon: LucideIcons.mic,
              label: 'Mikrofon',
              trailing: SizedBox.shrink(),
            ),
          ),
        ),
      );

      final titleLeft = tester.getTopLeft(find.text('Audio')).dx;
      final iconLeft = tester.getTopLeft(find.byIcon(LucideIcons.mic)).dx;

      expect(titleLeft, kSettingRowInset);
      expect(
        titleLeft,
        iconLeft,
        reason:
            'The section title and the icon of the row beneath it must share '
            'one reading edge — see `_headerTextInset` in section.dart.',
      );
    });
  });

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
            trailing: IconButton(icon: const Icon(Icons.add), onPressed: () {}),
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
