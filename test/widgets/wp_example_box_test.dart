import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/widgets/wp_example_box.dart';

import '../fixtures/test_helpers.dart';

void main() {
  testWidgets('shows the overline in capitals above the example', (
    tester,
  ) async {
    await tester.pumpWidget(
      makeTestable(
        const WpExampleBox(overline: 'Beispiel', child: Text('"Hallo Welt"')),
      ),
    );

    expect(find.text('BEISPIEL'), findsOneWidget);
    expect(find.text('"Hallo Welt"'), findsOneWidget);
  });

  testWidgets('places the example below the overline', (tester) async {
    await tester.pumpWidget(
      makeTestable(
        const WpExampleBox(overline: 'Beispiel', child: Text('Beispieltext')),
      ),
    );

    final overlineY = tester.getTopLeft(find.text('BEISPIEL')).dy;
    final exampleY = tester.getTopLeft(find.text('Beispieltext')).dy;
    expect(exampleY, greaterThan(overlineY));
  });
}
