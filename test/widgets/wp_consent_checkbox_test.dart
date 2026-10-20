import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/widgets/wp_consent_checkbox.dart';

import '../fixtures/test_helpers.dart';

void main() {
  Widget host(ValueChanged<bool> onChanged, {bool value = false}) =>
      makeTestable(
        Center(
          child: WpConsentCheckbox(
            value: value,
            onChanged: onChanged,
            label: 'Quote my feedback',
            explanation: 'Off by default.',
          ),
        ),
        locale: const Locale('en'),
      );

  testWidgets('starts unchecked and reports the label to assistive tech', (
    tester,
  ) async {
    await tester.pumpWidget(host((_) {}));

    final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
    expect(checkbox.value, isFalse);
    expect(find.text('Quote my feedback'), findsOneWidget);
    expect(find.text('Off by default.'), findsOneWidget);
  });

  testWidgets('tapping the label toggles the value to true', (tester) async {
    bool? seen;
    await tester.pumpWidget(host((v) => seen = v));

    await tester.tap(find.text('Quote my feedback'));
    await tester.pump();

    expect(seen, isTrue);
  });

  testWidgets('a checked box reports false when tapped again', (tester) async {
    bool? seen;
    await tester.pumpWidget(host((v) => seen = v, value: true));

    await tester.tap(find.text('Quote my feedback'));
    await tester.pump();

    expect(seen, isFalse);
  });
}
