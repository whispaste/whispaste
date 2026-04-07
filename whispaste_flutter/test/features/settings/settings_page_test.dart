import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/settings/settings_page.dart';

import '../../fixtures/test_helpers.dart';

void main() {
  group('SettingsPage', () {
    testWidgets('renders without error', (tester) async {
      await tester.pumpWidget(makeTestable(const SettingsPage()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows Audio section', (tester) async {
      await tester.pumpWidget(makeTestable(const SettingsPage()));
      await tester.pumpAndSettle();
      expect(find.text('Audio'), findsOneWidget);
    });

    testWidgets('shows Post-Processing section', (tester) async {
      await tester.pumpWidget(makeTestable(const SettingsPage()));
      await tester.pumpAndSettle();
      expect(find.textContaining('Post-Processing'), findsOneWidget);
    });

    testWidgets('shows Interface section', (tester) async {
      await tester.pumpWidget(makeTestable(const SettingsPage()));
      await tester.pumpAndSettle();
      expect(find.text('Interface'), findsOneWidget);
    });

    testWidgets('shows key setting labels', (tester) async {
      await tester.pumpWidget(makeTestable(const SettingsPage()));
      await tester.pumpAndSettle();

      expect(find.text('Microphone'), findsOneWidget);
      expect(find.text('Microphone Volume'), findsOneWidget);
      expect(find.text('Hold to Record'), findsOneWidget);
    });

    testWidgets('settings page is scrollable', (tester) async {
      await tester.pumpWidget(makeTestable(const SettingsPage()));
      await tester.pumpAndSettle();
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });

    testWidgets('shows new Sound & Feedback section', (tester) async {
      await tester.pumpWidget(makeTestable(const SettingsPage()));
      await tester.pumpAndSettle();
      // Scroll down to find the section
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -600),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sound & Feedback'), findsOneWidget);
    });

    testWidgets('shows new Overlay & Floating Button section', (tester) async {
      await tester.pumpWidget(makeTestable(const SettingsPage()));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -800),
      );
      await tester.pumpAndSettle();
      expect(find.text('Overlay & Floating Button'), findsOneWidget);
    });

    testWidgets('shows reset action', (tester) async {
      await tester.pumpWidget(makeTestable(const SettingsPage()));
      await tester.pumpAndSettle();
      expect(find.text('Reset to Defaults'), findsOneWidget);
    });
  });
}
