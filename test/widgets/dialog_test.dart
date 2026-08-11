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

/// Opens a plain content dialog — the shape the factory-reset progress
/// dialog and the history shortcut help now use.
Widget _contentDialogOpener({
  bool dismissible = true,
  String body = 'Deleting downloaded models…',
}) => Builder(
  builder: (context) => ElevatedButton(
    onPressed: () => showWpDialog<void>(
      context: context,
      title: 'Resetting WhisPaste',
      content: Text(body),
      dismissible: dismissible,
    ),
    child: const Text('Open dialog'),
  ),
);

Widget _formDialogOpener() => Builder(
  builder: (context) => ElevatedButton(
    onPressed: () => showWpFormDialog<void>(
      context: context,
      builder: (ctx, animation) => WpFormDialogShell(
        animation: animation,
        title: 'New Snippet',
        subtitle: 'Open the snippet picker while dictating to insert this.',
        fields: const [
          Text('Title'),
          TextField(),
          SizedBox(height: 12),
          Text('Body'),
          TextField(minLines: 3, maxLines: 6),
        ],
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    ),
    child: const Text('Open dialog'),
  ),
);

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

  group('dismissible', () {
    // The factory-reset progress dialog leans on this: a destructive
    // operation in flight must not be walked away from, and the capability
    // has to live here rather than in the call site (which is how that
    // dialog ended up as a raw AlertDialog in the first place).
    testWidgets('a dialog can be dismissed with Escape by default', (
      tester,
    ) async {
      await tester.pumpWidget(makeTestable(_contentDialogOpener()));
      await tester.tap(find.text('Open dialog'));
      await tester.pumpAndSettle();
      expect(find.text('Resetting WhisPaste'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.text('Resetting WhisPaste'), findsNothing);
    });

    testWidgets('dismissible: false survives Escape and a tap beside it', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(_contentDialogOpener(dismissible: false)),
      );
      await tester.tap(find.text('Open dialog'));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(
        find.text('Resetting WhisPaste'),
        findsOneWidget,
        reason: 'PopScope must block the Escape pop',
      );

      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(
        find.text('Resetting WhisPaste'),
        findsOneWidget,
        reason: 'the barrier must not dismiss the dialog either',
      );

      // The dialog still pops itself — that is how the reset dialog closes
      // on its terminal phase.
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.pop();
      await tester.pumpAndSettle();
      expect(find.text('Resetting WhisPaste'), findsNothing);
    });
  });

  group('form dialog shell', () {
    testWidgets('renders the explanatory subtitle under the title', (
      tester,
    ) async {
      await tester.pumpWidget(makeTestable(_formDialogOpener()));
      await tester.tap(find.text('Open dialog'));
      await tester.pumpAndSettle();

      expect(find.text('New Snippet'), findsOneWidget);
      expect(
        find.text('Open the snippet picker while dictating to insert this.'),
        findsOneWidget,
        reason:
            'every form dialog owes the user a sentence on what the input '
            'does — the shell is what guarantees it',
      );
    });
  });

  group('large system text', () {
    // Dialog routes live in the app's overlay, above any MediaQuery a test
    // shell installs — so the accessibility text size has to come from the
    // view, exactly like the real system setting does.
    setUp(() {
      TestWidgetsFlutterBinding
              .instance
              .platformDispatcher
              .textScaleFactorTestValue =
          2.0;
      addTearDown(
        TestWidgetsFlutterBinding
            .instance
            .platformDispatcher
            .clearTextScaleFactorTestValue,
      );
    });

    // The card clamps itself to the viewport and scrolls its body, so a 2x
    // text scale on an 800x600 window must not cut a dialog off.
    testWidgets('dark: a content dialog stays whole', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          _contentDialogOpener(
            body:
                'Deleting downloaded models, the transcript database, '
                'the secure store and every setting you have changed. '
                'This cannot be undone.',
          ),
        ),
      );
      await tester.tap(find.text('Open dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Resetting WhisPaste'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('dark: a form dialog stays whole', (tester) async {
      await tester.pumpWidget(makeTestable(_formDialogOpener()));
      await tester.tap(find.text('Open dialog'));
      await tester.pumpAndSettle();

      expect(find.text('New Snippet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
