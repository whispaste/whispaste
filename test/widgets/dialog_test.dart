import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/widgets/dialog.dart';

import '../fixtures/test_helpers.dart';

class _ConfirmDialogHarness extends StatefulWidget {
  const _ConfirmDialogHarness();

  @override
  State<_ConfirmDialogHarness> createState() => _ConfirmDialogHarnessState();
}

class _ConfirmDialogHarnessState extends State<_ConfirmDialogHarness> {
  bool? _result;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ElevatedButton(
            onPressed: () async {
              final result = await showWpConfirmDialog(
                context: context,
                title: 'Merge 2 entries?',
                message: 'The selected entries will be combined into one.',
                confirmLabel: 'Merge',
                cancelLabel: 'Cancel',
              );
              if (!mounted) return;
              setState(() => _result = result);
            },
            child: const Text('Open dialog'),
          ),
          Text("result=${_result ?? 'pending'}"),
        ],
      ),
    );
  }
}

void main() {
  testWidgets('confirm dialogs submit the primary action on Enter', (
    tester,
  ) async {
    await tester.pumpWidget(makeTestable(const _ConfirmDialogHarness()));

    await tester.tap(find.text('Open dialog'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Merge'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('result=true'), findsOneWidget);
  });
}
