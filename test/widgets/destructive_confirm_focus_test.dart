// UIA-CMP-02 — Enter (or a key still held while the dialog opens) never
// confirms a destructive dialog; Esc cancels it. Non-destructive
// confirmations still confirm on Enter.
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
  testWidgets('destructive confirm: Enter does nothing, Esc cancels', (
    tester,
  ) async {
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
      isNull,
      reason:
          'Enter must not answer a destructive '
          'confirmation',
    );
    expect(find.byKey(const ValueKey('confirm-dialog-confirm')), findsOne);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });

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
