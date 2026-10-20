import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/core/theme/generated/wp_tokens.g.dart';
import 'package:whispaste/widgets/wp_keycap.dart';

import '../fixtures/test_helpers.dart';

void main() {
  testWidgets('renders the key label', (tester) async {
    await tester.pumpWidget(makeTestable(const WpKeycap(label: 'Ctrl')));

    expect(find.text('Ctrl'), findsOneWidget);
  });

  testWidgets('draws a bordered cap in the default border role', (
    tester,
  ) async {
    await tester.pumpWidget(makeTestable(const WpKeycap(label: 'K')));

    final box = tester.widget<Container>(
      find.descendant(
        of: find.byType(WpKeycap),
        matching: find.byType(Container),
      ),
    );
    final decoration = box.decoration! as BoxDecoration;
    expect(decoration.border, isNotNull);
    expect((decoration.border! as Border).top.color, WpColors.borderDefault);
  });

  testWidgets('dock variant is frost on navy with a 30 % frost rim', (
    tester,
  ) async {
    await tester.pumpWidget(makeTestable(const WpKeycap.dock(label: 'Ctrl')));

    final box = tester.widget<Container>(
      find.descendant(
        of: find.byType(WpKeycap),
        matching: find.byType(Container),
      ),
    );
    final decoration = box.decoration! as BoxDecoration;
    expect(decoration.color, WpColorsDark.cardFill);
    final rim = (decoration.border! as Border).top.color;
    expect(rim, WpColorsDark.frostBorder30);
    expect(rim.toARGB32() >> 24, 0x4D, reason: 'frost at 30 % alpha');
    expect(
      decoration.borderRadius,
      BorderRadius.circular(WpRadiusTokens.control),
    );
    expect(WpRadiusTokens.control, 8);
  });
}
