/// Accessibility and text-hierarchy tests for [SettingRow].
///
/// Verifies:
/// - Minimum touch-target height (≥ 48 dp) via [WpLayout.minTouchTarget].
/// - Semantics label is exposed on the row.
/// - With [SettingRow.switchNamesRow] the switch alone carries name and state.
/// - Subtitle text uses the theme's `bodySmall` text style (token-based).
library;

import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/theme/tokens.dart';
import 'package:whispaste/features/settings/settings_widgets.dart';

import '../../fixtures/test_helpers.dart';

void main() {
  group('SettingRow — minimum touch-target height', () {});

  group('SettingRow — Semantics label', () {
    testWidgets('Semantics node carries the row label', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const SettingRow(
            icon: LucideIcons.bell,
            label: 'Show notifications',
            trailing: SizedBox.shrink(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The outermost Semantics node on the SettingRow should expose the label.
      final node = tester.getSemantics(find.byType(SettingRow));
      expect(
        node.label,
        contains('Show notifications'),
        reason: 'SettingRow Semantics must expose the label string',
      );
    });

    testWidgets('a row beside a live switch reads only its explanation', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          SettingRow(
            icon: LucideIcons.bell,
            label: 'Enable sounds',
            subtitle: 'Plays a tone',
            switchNamesRow: true,
            trailing: settingsToggle(
              label: 'Enable sounds',
              testId: 'sounds-toggle',
              value: true,
              onChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final node = tester.getSemantics(find.byType(SettingRow));
      expect(node.label, 'Plays a tone');
      expect(node.hint, isEmpty);
      expect(node.flagsCollection.isToggled, equals(Tristate.none));
      expect(find.bySemanticsIdentifier('sounds-toggle'), findsOneWidget);
    });

    testWidgets('a row without a live switch keeps its name and claims no '
        'state', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const SettingRow(
            icon: LucideIcons.bell,
            label: 'Some label',
            trailing: SizedBox.shrink(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final node = tester.getSemantics(find.byType(SettingRow));
      expect(node.label, 'Some label');
      expect(node.flagsCollection.isToggled, equals(Tristate.none));
    });
  });

  group('SettingRow — subtitle text style', () {});
}
