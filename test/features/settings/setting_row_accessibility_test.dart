/// Accessibility and text-hierarchy tests for [SettingRow].
///
/// Verifies:
/// - Minimum touch-target height (≥ 48 dp) via [WpLayout.minTouchTarget].
/// - Semantics label is exposed on the row.
/// - [SettingRow.semanticToggledValue] is reflected in the Semantics tree
///   so screen-readers announce toggle state alongside the label.
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
  group('SettingRow — minimum touch-target height', () {
    testWidgets('row without subtitle is ≥ 48 dp tall', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          SettingRow(
            icon: LucideIcons.bell,
            label: 'Notifications',
            trailing: Switch(value: false, onChanged: (_) {}),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final size = tester.getSize(find.byType(SettingRow));
      expect(
        size.height,
        greaterThanOrEqualTo(WpLayout.minTouchTarget),
        reason:
            'SettingRow must be ≥ ${WpLayout.minTouchTarget} dp tall '
            '(WCAG 2.5.5 target-size guideline)',
      );
    });

    testWidgets('row with subtitle is ≥ 48 dp tall', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          SettingRow(
            icon: LucideIcons.bell,
            label: 'Notifications',
            subtitle: 'Show alerts for completed recordings',
            trailing: Switch(value: true, onChanged: (_) {}),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final size = tester.getSize(find.byType(SettingRow));
      expect(
        size.height,
        greaterThanOrEqualTo(WpLayout.minTouchTarget),
        reason: 'SettingRow with subtitle must still be ≥ 48 dp tall',
      );
    });
  });

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

    testWidgets(
      'semanticToggledValue=true produces isToggled=isTrue on Semantics node',

      (tester) async {
        await tester.pumpWidget(
          makeTestable(
            SettingRow(
              icon: LucideIcons.bell,
              label: 'Enable sounds',
              semanticToggledValue: true,
              trailing: Switch(value: true, onChanged: (_) {}),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final node = tester.getSemantics(find.byType(SettingRow));
        // flagsCollection.isToggled is a Tristate (isTrue / isFalse / none).
        expect(
          node.flagsCollection.isToggled,
          equals(Tristate.isTrue),
          reason:
              'When semanticToggledValue is true, flagsCollection.isToggled '
              'must equal Tristate.isTrue so screen-readers say "on"',
        );
      },
    );

    testWidgets(
      'semanticToggledValue=false produces isToggled=isFalse on Semantics node',
      (tester) async {
        await tester.pumpWidget(
          makeTestable(
            SettingRow(
              icon: LucideIcons.bell,
              label: 'Enable sounds',
              semanticToggledValue: false,
              trailing: Switch(value: false, onChanged: (_) {}),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final node = tester.getSemantics(find.byType(SettingRow));
        expect(
          node.flagsCollection.isToggled,
          equals(Tristate.isFalse),
          reason:
              'When semanticToggledValue is false, flagsCollection.isToggled '
              'must equal Tristate.isFalse so screen-readers say "off"',
        );
      },
    );

    testWidgets(
      'without semanticToggledValue, isToggled is none on Semantics node',
      (tester) async {
        await tester.pumpWidget(
          makeTestable(
            const SettingRow(
              icon: LucideIcons.bell,
              label: 'Some label',
              trailing: SizedBox.shrink(),
              // semanticToggledValue intentionally absent
            ),
          ),
        );
        await tester.pumpAndSettle();

        final node = tester.getSemantics(find.byType(SettingRow));
        // Tristate.none means the flag is absent — the row is not a toggle.
        expect(
          node.flagsCollection.isToggled,
          equals(Tristate.none),
          reason:
              'Without semanticToggledValue, Semantics must not carry '
              'a toggled flag (non-toggle rows must not mislead screen-readers)',
        );
      },
    );
  });

  group('SettingRow — subtitle text style', () {
    testWidgets('subtitle renders at 12 dp font size (bodySmall)', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          const SettingRow(
            icon: LucideIcons.bell,
            label: 'Main label',
            subtitle: 'Subtitle text here',
            trailing: SizedBox.shrink(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find all Text widgets inside the SettingRow, locate the subtitle one.
      final subtitleFinder = find.text('Subtitle text here');
      expect(subtitleFinder, findsOneWidget);

      final richText = tester.widget<RichText>(
        find
            .descendant(of: subtitleFinder, matching: find.byType(RichText))
            .first,
      );
      final fontSize = richText.text.style?.fontSize;
      // bodySmall = 12 dp
      expect(
        fontSize,
        equals(12.0),
        reason: 'Subtitle must use bodySmall token (12 dp font size)',
      );
    });
  });
}
