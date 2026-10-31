import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/features/settings/widgets/wp_settings_group.dart';

import '../../../fixtures/test_helpers.dart';

Finder _row(String id) => find.byKey(ValueKey('settings-row-$id'));

Widget _group({required List<Widget> children, String? heading}) => Center(
  child: SizedBox(
    width: 560,
    child: WpSettingsGroup(heading: heading, children: children),
  ),
);

void main() {
  setUp(() => WpColors.activate(wpLightColors));
  tearDown(() => WpColors.activate(wpLightColors));

  testWidgets('label and toggled state merge into one semantics node', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      makeTestable(
        _group(
          children: const [
            WpSettingsRow(
              rowId: 'sem',
              title: 'Announce me',
              subtitle: 'Hint line',
              semanticToggledValue: true,
              trailing: Switch(value: true, onChanged: null),
            ),
          ],
        ),
      ),
    );

    final node = tester.getSemantics(_row('sem'));
    expect(node.label, 'Announce me');
    expect(node.hint, 'Hint line');
    expect(node.flagsCollection.isToggled, ui.Tristate.isTrue);
    handle.dispose();
  });

  testWidgets('disabledReason keeps the row, disables the control, explains', (
    tester,
  ) async {
    await tester.pumpWidget(
      makeTestable(
        _group(
          children: const [
            WpSettingsRow(
              rowId: 'store',
              title: 'Updates',
              subtitle: 'Checks for new versions',
              disabledReason: 'Updates come through the store here',
              trailing: Switch(value: false, onChanged: null),
            ),
          ],
        ),
      ),
    );

    expect(_row('store'), findsOneWidget);
    expect(find.text('Updates come through the store here'), findsOneWidget);
    expect(find.text('Checks for new versions'), findsNothing);
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
  });

  testWidgets(
    'keyboard: Tab reaches the trailing switch and Space toggles it',
    (tester) async {
      var value = false;
      await tester.pumpWidget(
        makeTestable(
          StatefulBuilder(
            builder: (context, setState) => _group(
              children: [
                WpSettingsRow(
                  rowId: 'key',
                  title: 'Keyboard',
                  trailing: Switch(
                    value: value,
                    onChanged: (v) => setState(() => value = v),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(value, isTrue);
    },
  );
}
