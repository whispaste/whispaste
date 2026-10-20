/// [WpToast.show] puts its test ID on the toast card, so a journey can find
/// the card and not only its text (DEV-147).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/widgets/toast.dart';

import '../fixtures/test_helpers.dart';

class _Harness extends StatelessWidget {
  const _Harness();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ElevatedButton(
        onPressed: () => WpToast.show(
          context,
          message: 'toast with an id',
          testId: 'pending-audio-toast',
        ),
        child: const Text('fire-toast'),
      ),
    );
  }
}

void main() {
  testWidgets('the card carries the test ID passed to show', (tester) async {
    await tester.pumpWidget(
      makeTestable(const _Harness(), locale: const Locale('en')),
    );

    await tester.tap(find.text('fire-toast'));
    await tester.pump();

    expect(find.byKey(const ValueKey('pending-audio-toast')), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });
}
