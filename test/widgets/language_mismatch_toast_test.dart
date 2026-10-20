/// 9.10: the wrong-language hint is a discreet info toast with a quick-switch
/// action that calls back with the action tap.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/widgets/recording_behavior.dart';

import '../fixtures/test_helpers.dart';

class _Trigger extends StatelessWidget {
  const _Trigger({required this.onSwitch});

  final VoidCallback onSwitch;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ElevatedButton(
        onPressed: () => showLanguageMismatchToast(
          context: context,
          l10n: L10n.of(context),
          onSwitch: onSwitch,
        ),
        child: const Text('fire'),
      ),
    );
  }
}

void main() {
  late L10n l10n;
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  testWidgets('shows the hint with a switch action that fires once', (
    tester,
  ) async {
    var switched = 0;
    await tester.pumpWidget(
      makeTestable(
        _Trigger(onSwitch: () => switched++),
        locale: const Locale('en'),
      ),
    );
    await tester.tap(find.text('fire'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text(l10n.languageMismatchHint), findsOneWidget);
    expect(find.text(l10n.languageMismatchSwitch), findsOneWidget);

    await tester.tap(find.text(l10n.languageMismatchSwitch));
    await tester.pump();
    expect(switched, 1);

    // Let the toast's 6 s auto-dismiss timer and its animation finish.
    await tester.pump(const Duration(seconds: 7));
    await tester.pump(const Duration(seconds: 1));
  });
}
