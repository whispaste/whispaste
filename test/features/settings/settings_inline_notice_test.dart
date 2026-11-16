// Settings notices appear after an action, so screen readers must hear them
// without a focus change (UIA-SET-12).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/settings/settings_widgets.dart';

import '../../fixtures/test_helpers.dart';

void main() {
  testWidgets('a settings inline notice is a live region (UIA-SET-12)', (
    tester,
  ) async {
    await tester.pumpWidget(
      makeTestable(
        Builder(
          builder: (context) => settingsInlineNotice(
            context: context,
            message: 'Input is clipping',
          ),
        ),
        locale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.liveRegion == true,
      ),
      findsOneWidget,
    );
  });
}
