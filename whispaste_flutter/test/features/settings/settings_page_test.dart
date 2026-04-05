import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/settings/settings_page.dart';

import '../../fixtures/test_helpers.dart';

void main() {
  group('SettingsPage', () {
    testWidgets('renders without error', (tester) async {
      await tester.pumpWidget(makeTestable(const SettingsPage()));
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows Audio section', (tester) async {
      await tester.pumpWidget(makeTestable(const SettingsPage()));
      expect(find.text('Audio'), findsOneWidget);
    });

    testWidgets('shows Text Enhancement section', (tester) async {
      await tester.pumpWidget(makeTestable(const SettingsPage()));
      expect(find.text('Text Enhancement'), findsOneWidget);
    });

    testWidgets('shows Interface section', (tester) async {
      await tester.pumpWidget(makeTestable(const SettingsPage()));
      expect(find.text('Interface'), findsOneWidget);
    });

    testWidgets('shows key setting labels', (tester) async {
      await tester.pumpWidget(makeTestable(const SettingsPage()));

      expect(find.text('Microphone'), findsOneWidget);
      expect(find.text('Microphone Volume'), findsOneWidget);
      expect(find.text('Hold to Record'), findsOneWidget);
    });

    testWidgets('settings page is scrollable', (tester) async {
      await tester.pumpWidget(makeTestable(const SettingsPage()));
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });

    testWidgets('collapsible sections can be toggled', (tester) async {
      await tester.pumpWidget(makeTestable(const SettingsPage()));

      // Recording Safety is collapsible and initially expanded
      expect(find.text('Recording Safety'), findsOneWidget);
      expect(find.text('Silent Mic Detection'), findsOneWidget);

      // Tap header to collapse
      await tester.tap(find.text('Recording Safety'));
      await tester.pumpAndSettle();

      // Content should now be collapsed (heightFactor → 0)
      final aligns = tester.widgetList<Align>(find.byType(Align));
      final collapsed = aligns.any((a) => a.heightFactor == 0.0);
      expect(collapsed, isTrue);
    });
  });
}
