/// Regression guard for a defect class that had spread across the app: a
/// `Semantics(label: X)` wrapped around a subtree that *also* renders
/// `Text(X)`.
///
/// The framework does not treat such a label as a replacement for the
/// subtree's text — it is prepended to it. Every control built that way was
/// therefore announced twice ("Kopieren, Kopieren"), and the pattern had
/// reached the snippet picker, the export picker, the tag input, the status
/// bar, the hero button, the segmented selector and every settings row.
///
/// The house fix has two shapes, one per situation, and both are asserted
/// here so neither can silently regress:
///
///  * composed control, one tap target → `MergeSemantics` + a *label-less*
///    `Semantics`, so the name folds in from the rendered text while the
///    button role and the tap action survive the fold;
///  * settings row, arbitrary trailing control → no wrapper label at all and
///    deliberately no `MergeSemantics`, because merging would swallow a text
///    field or a slider into the row.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/features/settings/settings_widgets.dart';
import 'package:whispaste/widgets/wp_hero_button.dart';

import '../../fixtures/test_helpers.dart';

void main() {
  group('no double announcement', () {
    testWidgets('WpHeroButton announces its caption exactly once', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          makeTestable(
            Center(
              child: WpHeroButton(
                label: 'Weiter',
                onPressed: () {},
                gradient: const LinearGradient(
                  colors: [Colors.teal, Colors.cyan],
                ),
              ),
            ),
          ),
        );

        // "Weiter" once — not "Weiter\nWeiter" — and the fold must not cost
        // the button its role or its tap action.
        expect(
          tester.getSemantics(find.byType(WpHeroButton)),
          matchesSemantics(
            label: 'Weiter',
            isButton: true,
            isEnabled: true,
            hasEnabledState: true,
            hasTapAction: true,
            hasFocusAction: true,
            isFocusable: true,
          ),
        );
      } finally {
        handle.dispose();
      }
    });

    testWidgets('SettingRow names itself once and keeps its toggle separate', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          makeTestable(
            Center(
              child: SettingRow(
                icon: LucideIcons.bell,
                label: 'Benachrichtigungen',
                subtitle: 'Beim Abschluss einer Aufnahme',
                semanticToggledValue: true,
                trailing: settingsToggle(value: true, onChanged: (_) {}),
              ),
            ),
          ),
        );

        // The row node carries label and subtitle exactly once each. Before
        // the fix this read "Benachrichtigungen, Benachrichtigungen, Beim
        // Abschluss einer Aufnahme" and then repeated the subtitle a third
        // time as the node's hint.
        expect(
          tester.getSemantics(find.byType(SettingRow)),
          matchesSemantics(
            label: 'Benachrichtigungen',
            hint: 'Beim Abschluss einer Aufnahme',
            hasToggledState: true,
            isToggled: true,
          ),
        );

        // …and the Switch stays its own operable node rather than being
        // folded into the row. This is why SettingRow is pointedly *not*
        // wrapped in MergeSemantics like the single-target controls above.
        expect(
          tester.getSemantics(find.byType(Switch)),
          matchesSemantics(
            hasToggledState: true,
            isToggled: true,
            hasEnabledState: true,
            isEnabled: true,
            hasTapAction: true,
            hasFocusAction: true,
            isFocusable: true,
          ),
        );
      } finally {
        handle.dispose();
      }
    });
  });
}
