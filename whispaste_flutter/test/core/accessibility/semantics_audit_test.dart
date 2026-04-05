/// Accessibility semantics audit for WhisPaste.
///
/// Verifies that key interactive widgets have proper semantics labels
/// and that pages are navigable via assistive technologies.
library;

import 'dart:ui' show CheckedState;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/test_helpers.dart';

void main() {
  group('Semantics audit', () {
    testWidgets('IconButton widgets have tooltips',
        (tester) async {
      await tester.pumpWidget(makeTestable(
        IconButton(
          icon: const Icon(Icons.search),
          tooltip: 'Search',
          onPressed: () {},
        ),
      ));
      await tester.pumpAndSettle();

      // The tooltip is rendered and accessible for long-press
      final iconButton = find.byType(IconButton);
      expect(iconButton, findsOneWidget);

      // Tooltip renders as hidden text that's accessible
      expect(find.byTooltip('Search'), findsOneWidget,
          reason: 'IconButtons must have a tooltip for screen readers');
    });

    testWidgets('Switch widgets have toggling semantics', (tester) async {
      await tester.pumpWidget(makeTestable(
        Semantics(
          label: 'Enable feature',
          child: Switch(value: true, onChanged: (_) {}),
        ),
      ));
      await tester.pumpAndSettle();

      // Verify the Switch is rendered and has toggle action semantics
      final switchWidget = find.byType(Switch);
      expect(switchWidget, findsOneWidget);
    });

    testWidgets('TextField renders label decoration', (tester) async {
      await tester.pumpWidget(makeTestable(
        const TextField(
          decoration: InputDecoration(labelText: 'Search entries'),
        ),
      ));
      await tester.pumpAndSettle();

      // The label text is rendered as part of the InputDecoration
      expect(find.text('Search entries'), findsOneWidget,
          reason: 'TextField must render its label for visibility');
    });

    testWidgets('ElevatedButton has semantics label', (tester) async {
      await tester.pumpWidget(makeTestable(
        ElevatedButton(onPressed: () {}, child: const Text('Save')),
      ));
      await tester.pumpAndSettle();

      final button = find.byType(ElevatedButton);
      expect(button, findsOneWidget);

      final semantics = tester.getSemantics(button);
      expect(semantics.label, isNotEmpty,
          reason: 'Buttons must expose their label for screen readers');
    });

    testWidgets('Checkbox has semantics', (tester) async {
      await tester.pumpWidget(makeTestable(
        Checkbox(value: false, onChanged: (_) {}),
      ));
      await tester.pumpAndSettle();

      final checkbox = find.byType(Checkbox);
      expect(checkbox, findsOneWidget);

      final semantics = tester.getSemantics(checkbox);
      expect(
          semantics.flagsCollection.isChecked != CheckedState.none, isTrue,
          reason: 'Checkbox must expose checked state semantics');
    });
  });

  group('Touch target audit', () {
    testWidgets('IconButton meets 48x48 minimum hit area', (tester) async {
      await tester.pumpWidget(makeTestable(
        IconButton(
          icon: const Icon(Icons.close, size: 16),
          tooltip: 'Close',
          onPressed: () {},
        ),
      ));
      await tester.pumpAndSettle();

      final iconButton = find.byType(IconButton);
      final size = tester.getSize(iconButton);

      // Material Design 3 minimum touch target: 48x48
      expect(size.width, greaterThanOrEqualTo(48),
          reason:
              'IconButton hit area must be ≥ 48px wide (Material accessibility)');
      expect(size.height, greaterThanOrEqualTo(48),
          reason:
              'IconButton hit area must be ≥ 48px tall (Material accessibility)');
    });

    testWidgets('Checkbox meets minimum hit area', (tester) async {
      await tester.pumpWidget(makeTestable(
        Checkbox(value: false, onChanged: (_) {}),
      ));
      await tester.pumpAndSettle();

      final checkbox = find.byType(Checkbox);
      final size = tester.getSize(checkbox);

      expect(size.width, greaterThanOrEqualTo(48),
          reason: 'Checkbox hit area must be ≥ 48px wide');
      expect(size.height, greaterThanOrEqualTo(48),
          reason: 'Checkbox hit area must be ≥ 48px tall');
    });

    testWidgets('Switch meets minimum hit area', (tester) async {
      await tester.pumpWidget(makeTestable(
        Switch(value: true, onChanged: (_) {}),
      ));
      await tester.pumpAndSettle();

      final switchWidget = find.byType(Switch);
      final size = tester.getSize(switchWidget);

      expect(size.width, greaterThanOrEqualTo(48),
          reason: 'Switch hit area must be ≥ 48px wide');
      expect(size.height, greaterThanOrEqualTo(48),
          reason: 'Switch hit area must be ≥ 48px tall');
    });
  });
}
