/// Tests for the paste-failure toast wired in `recording_behavior.dart`.
///
/// Mirrors the extracted-helper pattern from `recovery_toast_test.dart` /
/// `cpu_fallback_toast_test.dart`: [showPasteFailureToast] is exercised
/// through a minimal harness widget, so no app-shell/overlay bootstrapping
/// is required to prove which message (and action button, if any) a given
/// [PasteOutcome] renders.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/services/paste/paster.dart';
import 'package:whispaste/widgets/recording_behavior.dart';

import '../fixtures/test_helpers.dart';

class _PasteFailureHarness extends StatelessWidget {
  const _PasteFailureHarness(this.outcome);

  final PasteOutcome outcome;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ElevatedButton(
        onPressed: () => showPasteFailureToast(
          context: context,
          l10n: L10n.of(context),
          outcome: outcome,
        ),
        child: const Text('fire-paste-failure-toast'),
      ),
    );
  }
}

void main() {
  late L10n lDe;
  late L10n lEn;
  setUpAll(() async {
    lDe = await L10n.delegate.load(const Locale('de'));
    lEn = await L10n.delegate.load(const Locale('en'));
  });

  group('showPasteFailureToast — elevationBlocked (Windows UIPI)', () {
    testWidgets('renders a distinct message, no action button (de)', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          const _PasteFailureHarness(PasteOutcome.elevationBlocked),
          locale: const Locale('de'),
        ),
      );

      await tester.tap(find.text('fire-paste-failure-toast'));
      await tester.pumpAndSettle();

      expect(find.text(lDe.pasteFailureElevationBlocked), findsOneWidget);
      // Distinct from the generic bucket — must not fall back to it.
      expect(find.text(lDe.pasteFailureGeneric), findsNothing);
      // No action button: there is no clean way to relaunch WhisPaste
      // elevated from inside the running process, so an honest
      // informational message without a button is correct here.
      expect(find.byType(TextButton), findsNothing);

      await tester.pumpAndSettle(const Duration(seconds: 6));
    });

    testWidgets('en locale: English copy matches the ARB entry', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          const _PasteFailureHarness(PasteOutcome.elevationBlocked),
          locale: const Locale('en'),
        ),
      );

      await tester.tap(find.text('fire-paste-failure-toast'));
      await tester.pumpAndSettle();

      expect(find.text(lEn.pasteFailureElevationBlocked), findsOneWidget);

      await tester.pumpAndSettle(const Duration(seconds: 6));
    });
  });
}
