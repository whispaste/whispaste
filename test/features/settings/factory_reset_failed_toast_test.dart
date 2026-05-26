/// Widget test for the factory-reset-failed actionable toast seam in
/// `cloud_advanced_section.dart`.
///
/// Covers AC5 from
/// `.scratch/reliability-sprint/issues/07-feat-actionable-toast-polish.md`:
/// the failed-reset toast must render the „App schließen" action which
/// calls `exit(0)` (or the platform-conforming close method). The
/// production `factoryResetExitFn` defaults to `dart:io`'s `exit`; this
/// test swaps in a spy so we can assert the action fires without
/// terminating the test isolate.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/settings/sections/cloud_advanced_section.dart';
import 'package:whispaste/widgets/toast.dart';

import '../../fixtures/test_helpers.dart';

/// Re-renders the same toast surface as
/// `cloud_advanced_section._confirmFactoryReset` does on the failure
/// branch. Kept inline here so the test exercises the real
/// [factoryResetExitFn] seam end-to-end without driving the full
/// FactoryResetCoordinator stream.
class _FailedToastHarness extends StatelessWidget {
  const _FailedToastHarness();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ElevatedButton(
        onPressed: () {
          final l10n = L10n.of(context);
          WpToast.show(
            context,
            message: l10n.factoryResetFailedToast,
            type: WpToastType.error,
            duration: const Duration(seconds: 8),
            action: WpToastAction(
              label: l10n.factoryResetFailedAction,
              onPressed: () => factoryResetExitFn(0),
            ),
          );
        },
        child: const Text('fire-failed-toast'),
      ),
    );
  }
}

void main() {
  group('factory-reset-failed actionable toast', () {
    late ExitFn originalExit;

    setUp(() {
      originalExit = factoryResetExitFn;
    });

    tearDown(() {
      factoryResetExitFn = originalExit;
    });

    testWidgets(
      'renders "App schließen" and invokes the exit seam with code 0 on tap',
      (tester) async {
        final exitCalls = <int>[];
        factoryResetExitFn = exitCalls.add;

        await tester.pumpWidget(
          makeTestable(const _FailedToastHarness(), locale: const Locale('de')),
        );

        await tester.tap(find.text('fire-failed-toast'));
        await tester.pumpAndSettle();

        expect(
          find.text('Werks-Reset unvollständig. App neu starten?'),
          findsOneWidget,
        );
        expect(find.text('App schließen'), findsOneWidget);
        expect(exitCalls, isEmpty);

        await tester.tap(find.text('App schließen'));
        await tester.pumpAndSettle();

        expect(
          exitCalls,
          [0],
          reason: 'tapping the action must call exit(0) via the test seam',
        );

        // Drain the toast's 8s auto-dismiss timer so no Timer outlives
        // the test.
        await tester.pumpAndSettle(const Duration(seconds: 9));
      },
    );

    testWidgets('English locale matches the ARB entry', (tester) async {
      factoryResetExitFn = (_) {};

      await tester.pumpWidget(
        makeTestable(const _FailedToastHarness(), locale: const Locale('en')),
      );

      await tester.tap(find.text('fire-failed-toast'));
      await tester.pumpAndSettle();

      expect(
        find.text('Factory reset incomplete. Restart the app?'),
        findsOneWidget,
      );
      expect(find.text('Quit app'), findsOneWidget);

      // Drain the toast's 8s auto-dismiss timer so no Timer outlives
      // the test.
      await tester.pumpAndSettle(const Duration(seconds: 9));
    });
  });
}
