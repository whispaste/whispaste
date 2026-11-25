/// Dialogs in the semantics tree (#1924): the barrier behind a dialog is no
/// element of its own (on macOS it was a window-wide "Schließen" text), and
/// the title is the heading that names the dialog.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/widgets/dialog.dart';

import '../fixtures/test_helpers.dart';

void main() {
  testWidgets(
    'no barrier node, the title names the dialog',
    variant: TargetPlatformVariant.desktop(),
    (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        makeTestable(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showWpDialog<void>(
                context: context,
                title: 'New profile',
                content: const Text('Body'),
              ),
              child: const Text('Open dialog'),
            ),
          ),
          locale: const Locale('en'),
        ),
      );
      await tester.tap(find.text('Open dialog'));
      await tester.pumpAndSettle();

      final dismissLabel = MaterialLocalizations.of(
        tester.element(find.text('Body')),
      ).modalBarrierDismissLabel;
      expect(find.bySemanticsLabel(dismissLabel), findsNothing);

      final title = tester.getSemantics(find.text('New profile'));
      expect(title.label, 'New profile');
      expect(title.flagsCollection.isHeader, isTrue);
      expect(title.flagsCollection.namesRoute, isTrue);
      handle.dispose();
    },
  );
}
