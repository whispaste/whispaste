import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/core/theme/tokens.dart';
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

  testWidgets('renders the heading and separates children with dividers', (
    tester,
  ) async {
    await tester.pumpWidget(
      makeTestable(
        _group(
          heading: 'Updates',
          children: [
            const WpSettingsRow(
              rowId: 'one',
              title: 'First',
              trailing: Switch(value: true, onChanged: null),
            ),
            const WpSettingsRow(
              rowId: 'two',
              title: 'Second',
              trailing: Switch(value: false, onChanged: null),
            ),
            const WpSettingsRow(
              rowId: 'three',
              title: 'Third',
              trailing: Switch(value: false, onChanged: null),
            ),
          ],
        ),
      ),
    );

    expect(find.text('Updates'), findsOneWidget);
    // One divider between each pair of rows, none before the first or after
    // the last.
    expect(find.byType(Divider), findsNWidgets(2));
  });

  testWidgets('a spacer between two rows adds air but no second divider', (
    tester,
  ) async {
    await tester.pumpWidget(
      makeTestable(
        _group(
          children: [
            const WpSettingsRow(
              rowId: 'one',
              title: 'First',
              trailing: Switch(value: true, onChanged: null),
            ),
            const SizedBox(height: WpSpacing.md),
            const WpSettingsRow(
              rowId: 'two',
              title: 'Second',
              trailing: Switch(value: false, onChanged: null),
            ),
          ],
        ),
      ),
    );

    expect(find.byType(Divider), findsOneWidget);
    final firstBottom = tester.getRect(_row('one')).bottom;
    final secondTop = tester.getRect(_row('two')).top;
    final rule = tester.getRect(find.byType(Divider)).top;
    expect(rule, inInclusiveRange(firstBottom, secondTop));
  });

  testWidgets('card uses cardFill and a 12 px radius, no icon in the row', (
    tester,
  ) async {
    await tester.pumpWidget(
      makeTestable(
        _group(
          children: const [
            WpSettingsRow(
              rowId: 'plain',
              title: 'Plain row',
              subtitle: 'Explains the setting',
              trailing: Switch(value: true, onChanged: null),
            ),
          ],
        ),
      ),
    );

    final card = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('settings-group-card')),
    );
    final decoration = card.decoration as BoxDecoration;
    expect(decoration.color, WpColors.cardFill);
    expect(decoration.borderRadius, BorderRadius.circular(12));
    expect(WpRadius.md, 12);

    expect(
      find.descendant(of: _row('plain'), matching: find.byType(Icon)),
      findsNothing,
    );
  });

  testWidgets('row has 20 px inner text inset and 12 px vertical padding', (
    tester,
  ) async {
    await tester.pumpWidget(
      makeTestable(
        _group(
          children: const [
            WpSettingsRow(
              rowId: 'geo',
              title: 'Geometry',
              trailing: Switch(value: true, onChanged: null),
            ),
          ],
        ),
      ),
    );

    final card = tester.getRect(
      find.byKey(const ValueKey('settings-group-card')),
    );
    final title = tester.getRect(find.text('Geometry'));
    final row = tester.getRect(_row('geo'));

    expect(title.left - card.left, WpSpacing.lg);
    expect(title.top - row.top, greaterThanOrEqualTo(WpSpacing.sm));
    expect(row.height - title.height, greaterThanOrEqualTo(WpSpacing.sm * 2));
  });

  testWidgets('indent moves the text of a dependent row to the right', (
    tester,
  ) async {
    await tester.pumpWidget(
      makeTestable(
        _group(
          children: const [
            WpSettingsRow(
              rowId: 'parent',
              title: 'Parent',
              trailing: Switch(value: true, onChanged: null),
            ),
            WpSettingsRow(
              rowId: 'child',
              title: 'Child',
              indent: true,
              trailing: Switch(value: true, onChanged: null),
            ),
          ],
        ),
      ),
    );

    final parentLeft = tester.getRect(find.text('Parent')).left;
    final childLeft = tester.getRect(find.text('Child')).left;
    expect(childLeft - parentLeft, WpSpacing.xl);
  });

  testWidgets('trailing control never overflows at 800x600 or text scale 1.3', (
    tester,
  ) async {
    const longTitle =
        'A setting with a rather long title that has to wrap across lines';
    for (final scale in <double>[1.0, 1.3]) {
      await tester.pumpWidget(
        makeTestable(
          MediaQuery(
            data: MediaQueryData(
              size: const Size(800, 600),
              textScaler: TextScaler.linear(scale),
            ),
            child: _group(
              children: [
                const WpSettingsRow(
                  rowId: 'wide',
                  title: longTitle,
                  subtitle: 'An explanation that is also rather long.',
                  // At the 420 px cap the row stacks the control under the label
                  // when it is narrower than the stacking width.
                  trailing: SizedBox(
                    width: 420,
                    child: Row(
                      children: [
                        Expanded(child: Text('Trailing text')),
                        Switch(value: true, onChanged: null),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          size: const Size(800, 600),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'scale $scale');
    }
  });

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

  // The control stacks only when the title and its measured width no longer
  // fit side by side; a switch stays inline at 600 px.
  // Short enough for the test font (Ahem, one em per glyph) to fit beside a switch.
  const longTitle = 'Transcription language';

  Widget narrowGroup(Widget trailing, {double width = 600}) => makeTestable(
    Center(
      child: SizedBox(
        width: width,
        child: WpSettingsGroup(
          children: [
            WpSettingsRow(rowId: 'fit', title: longTitle, trailing: trailing),
          ],
        ),
      ),
    ),
  );

  testWidgets('a switch stays beside the title at 600 px', (tester) async {
    await tester.pumpWidget(
      narrowGroup(const Switch(value: true, onChanged: null)),
    );
    await tester.pumpAndSettle();

    final titleTop = tester.getTopLeft(find.text(longTitle)).dy;
    final switchTop = tester.getTopLeft(find.byType(Switch)).dy;
    expect((switchTop - titleTop).abs(), lessThan(20));
  });

  testWidgets('a wide control stacks under the title at 600 px', (
    tester,
  ) async {
    // A 420 px box stands in for a wide dropdown at its width cap.
    await tester.pumpWidget(
      narrowGroup(const SizedBox(width: 420, height: 40)),
    );
    await tester.pumpAndSettle();

    final titleTop = tester.getTopLeft(find.text(longTitle)).dy;
    final controlTop = tester.getTopLeft(find.byType(SizedBox).last).dy;
    expect(controlTop, greaterThan(titleTop + 20));
  });

  testWidgets('a wide control in a narrow row stacks on the first frame', (
    tester,
  ) async {
    // A single pump, no settle: the first frame must already be stacked and
    // must not overflow (the test framework fails on any RenderFlex overflow).
    await tester.pumpWidget(
      narrowGroup(const SizedBox(width: 420, height: 40), width: 300),
    );

    final titleTop = tester.getTopLeft(find.text(longTitle)).dy;
    final controlTop = tester.getTopLeft(find.byType(SizedBox).last).dy;
    expect(controlTop, greaterThan(titleTop + 20));
  });

  testWidgets('an RTL row puts the switch on the left, label on the right', (
    tester,
  ) async {
    await tester.pumpWidget(
      makeTestable(
        const Directionality(
          textDirection: TextDirection.rtl,
          child: Center(
            child: SizedBox(
              width: 600,
              child: WpSettingsGroup(
                children: [
                  WpSettingsRow(
                    rowId: 'rtl',
                    title: longTitle,
                    trailing: Switch(value: true, onChanged: null),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final titleRight = tester.getTopRight(find.text(longTitle)).dx;
    final switchLeft = tester.getTopLeft(find.byType(Switch)).dx;
    expect(switchLeft, lessThan(titleRight));
  });
}
