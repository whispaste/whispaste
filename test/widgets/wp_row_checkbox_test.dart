/// WpRowCheckbox exposes a screen-reader label (UIA-CMP-11).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/widgets/wp_row_checkbox.dart';

import '../fixtures/test_helpers.dart';

void main() {
  testWidgets('checkbox carries the label passed by its row', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      makeTestable(
        WpRowCheckbox(
          value: false,
          semanticsLabel: 'Fachbegriff',
          onChanged: () {},
        ),
      ),
    );

    expect(
      tester.getSemantics(find.bySemanticsLabel('Fachbegriff')),
      matchesSemantics(
        label: 'Fachbegriff',
        isChecked: false,
        hasCheckedState: true,
        hasTapAction: true,
        hasFocusAction: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
      ),
    );
    handle.dispose();
  });
}
