import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/features/settings/widgets/wp_appearance_picker.dart';

import '../../../fixtures/test_helpers.dart';

Finder _card(AppearanceMode mode) =>
    find.byKey(ValueKey('settings-appearance-card-${mode.value}'));

/// The card's visual box, the outermost Container inside the card.
Finder _box(AppearanceMode mode) =>
    find.descendant(of: _card(mode), matching: find.byType(Container)).first;

Widget _picker({
  required AppearanceMode mode,
  Brightness platform = Brightness.light,
  ValueChanged<AppearanceMode>? onChanged,
}) => Center(
  child: SizedBox(
    width: 640,
    child: WpAppearancePicker(
      mode: mode,
      platformBrightness: platform,
      onChanged: onChanged ?? (_) {},
    ),
  ),
);

void main() {
  setUp(() => WpColors.activate(wpLightColors));
  tearDown(() => WpColors.activate(wpLightColors));

  testWidgets('shows three cards: Light, Dark and Navy', (tester) async {
    await tester.pumpWidget(makeTestable(_picker(mode: AppearanceMode.light)));

    expect(_card(AppearanceMode.light), findsOneWidget);
    expect(_card(AppearanceMode.dark), findsOneWidget);
    expect(_card(AppearanceMode.navy), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
    expect(find.text('Navy'), findsOneWidget);
  });

  testWidgets('tapping a card writes its AppearanceMode', (tester) async {
    AppearanceMode? picked;
    await tester.pumpWidget(
      makeTestable(
        _picker(mode: AppearanceMode.light, onChanged: (m) => picked = m),
      ),
    );

    await tester.tap(_card(AppearanceMode.dark));
    expect(picked, AppearanceMode.dark);
  });

  testWidgets('each card is a button and exposes its selected state', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(makeTestable(_picker(mode: AppearanceMode.navy)));

    final brand = tester.getSemantics(_card(AppearanceMode.navy));
    expect(brand.label, contains('Navy'));
    expect(brand.flagsCollection.isSelected, ui.Tristate.isTrue);
    expect(brand.flagsCollection.isButton, isTrue);

    final light = tester.getSemantics(_card(AppearanceMode.light));
    expect(light.flagsCollection.isSelected, ui.Tristate.isFalse);
    handle.dispose();
  });

  testWidgets('with System active the resolved set shows as selected', (
    tester,
  ) async {
    await tester.pumpWidget(
      makeTestable(
        _picker(mode: AppearanceMode.system, platform: Brightness.dark),
      ),
    );

    final decoration =
        tester.widget<Container>(_box(AppearanceMode.dark)).decoration
            as BoxDecoration;
    expect(decoration.color, WpColors.accentSubtle);
    final lightDecoration =
        tester.widget<Container>(_box(AppearanceMode.light)).decoration
            as BoxDecoration;
    expect(lightDecoration.color, isNot(WpColors.accentSubtle));
  });

  testWidgets('keyboard: arrows move focus, Enter and Space select', (
    tester,
  ) async {
    final picked = <AppearanceMode>[];
    await tester.pumpWidget(
      makeTestable(_picker(mode: AppearanceMode.light, onChanged: picked.add)),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(_hasFocus(tester, AppearanceMode.light), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(_hasFocus(tester, AppearanceMode.dark), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(picked, [AppearanceMode.dark]);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(picked, [AppearanceMode.dark, AppearanceMode.navy]);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(_hasFocus(tester, AppearanceMode.dark), isTrue);
  });

  group('WpFollowSystemSwitch', () {
    testWidgets('is on exactly when the mode is System', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          Center(
            child: WpFollowSystemSwitch(
              mode: AppearanceMode.system,
              platformBrightness: Brightness.light,
              onChanged: (_) {},
            ),
          ),
        ),
      );
      expect(
        tester
            .widget<Switch>(
              find.byKey(const ValueKey('settings-appearance-follow-system')),
            )
            .value,
        isTrue,
      );
    });

    testWidgets('turning it off selects the set the system resolves to', (
      tester,
    ) async {
      AppearanceMode? written;
      await tester.pumpWidget(
        makeTestable(
          Center(
            child: WpFollowSystemSwitch(
              mode: AppearanceMode.system,
              platformBrightness: Brightness.dark,
              onChanged: (m) => written = m,
            ),
          ),
        ),
      );

      await tester.tap(
        find.byKey(const ValueKey('settings-appearance-follow-system')),
      );
      expect(written, AppearanceMode.dark);
    });

    testWidgets('turning it on writes System', (tester) async {
      AppearanceMode? written;
      await tester.pumpWidget(
        makeTestable(
          Center(
            child: WpFollowSystemSwitch(
              mode: AppearanceMode.light,
              platformBrightness: Brightness.light,
              onChanged: (m) => written = m,
            ),
          ),
        ),
      );

      await tester.tap(
        find.byKey(const ValueKey('settings-appearance-follow-system')),
      );
      expect(written, AppearanceMode.system);
    });
  });
}

bool _hasFocus(WidgetTester tester, AppearanceMode mode) =>
    Focus.of(tester.element(_box(mode))).hasFocus;
