/// UIA-SHL-06: "Try a smaller model" with no smaller model left must say why
/// nothing changed, instead of closing the dialog in silence.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/widgets/recording_behavior.dart';

import '../fixtures/test_helpers.dart';

class _OomHarness extends StatelessWidget {
  const _OomHarness();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ElevatedButton(
        onPressed: () => showOomNoSmallerModelToast(
          context: context,
          l10n: L10n.of(context),
        ),
        child: const Text('fire-oom-toast'),
      ),
    );
  }
}

void main() {
  testWidgets('shows the reason and the next step as an error toast', (
    tester,
  ) async {
    await tester.pumpWidget(
      makeTestable(const _OomHarness(), locale: const Locale('de')),
    );

    await tester.tap(find.text('fire-oom-toast'));
    await tester.pumpAndSettle();

    final lDe = await L10n.delegate.load(const Locale('de'));
    expect(find.text(lDe.oomRecoveryNoSmallerModel), findsOneWidget);

    await tester.pumpAndSettle(const Duration(seconds: 10));
  });
}
