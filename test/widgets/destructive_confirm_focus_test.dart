// UIA-CMP-02 — a destructive confirm dialog must focus "Cancel", so pressing
// Enter (or still holding it while the dialog opens) does not delete anything.
// Non-destructive confirmations keep the confirm button focused.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/widgets/dialog.dart';

import '../fixtures/test_helpers.dart';

Widget _host(ValueChanged<bool?> onResult, {required bool destructive}) {
  return makeTestable(
    Builder(
      builder: (context) => TextButton(
        onPressed: () async {
          final confirmed = await showWpConfirmDialog(
            context: context,
            title: 'Delete?',
            message: 'This cannot be undone.',
            confirmLabel: 'Delete',
            cancelLabel: 'Cancel',
            destructive: destructive,
          );
          onResult(confirmed);
        },
        child: const Text('open'),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'destructive confirm: Enter activates Cancel, not the delete button',
    (tester) async {
      bool? result;
      await tester.pumpWidget(
        _host((value) => result = value, destructive: true),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(
        result,
        isFalse,
        reason: 'Enter must not confirm a destructive action',
      );
    },
  );

  testWidgets('non-destructive confirm: Enter still confirms', (tester) async {
    bool? result;
    await tester.pumpWidget(
      _host((value) => result = value, destructive: false),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(result, isTrue);
  });
}
