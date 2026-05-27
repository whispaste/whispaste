/// Widget tests for the extracted [showRecoveryToast] helper from
/// `recording_behavior.dart`.
///
/// Covers AC4 (RecoveryExhausted → "Einstellungen öffnen" action
/// navigates to the advanced section) and the modelAbiInfo passive
/// toast surface. The injection of [openSettings] is the test seam
/// that lets us verify the navigation request fires without booting
/// the full app-shell — production wires it to
/// `_openSettings`, which writes `settingsScrollTargetProvider` and
/// `activePageProvider`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/services/stt/recovery_toast_notifier.dart';
import 'package:whispaste/widgets/recording_behavior.dart';

import '../fixtures/test_helpers.dart';

class _RecoveryHarness extends StatelessWidget {
  const _RecoveryHarness({required this.kind, required this.openSettings});

  final RecoveryToastKind kind;
  final void Function(String) openSettings;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ElevatedButton(
        onPressed: () => showRecoveryToast(
          context: context,
          l10n: L10n.of(context),
          kind: kind,
          openSettings: openSettings,
        ),
        child: const Text('fire-recovery-toast'),
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

  group('showRecoveryToast', () {
    testWidgets(
      'exhausted: renders error toast + "Einstellungen öffnen" action that '
      'requests advanced settings on tap',
      (tester) async {
        final navTargets = <String>[];

        await tester.pumpWidget(
          makeTestable(
            _RecoveryHarness(
              kind: RecoveryToastKind.exhausted,
              openSettings: navTargets.add,
            ),
            locale: const Locale('de'),
          ),
        );

        await tester.tap(find.text('fire-recovery-toast'));
        await tester.pumpAndSettle();

        expect(find.text(lDe.recoveryExhaustedToast), findsOneWidget);
        expect(find.text(lDe.recoveryExhaustedAction), findsOneWidget);
        expect(navTargets, isEmpty);

        await tester.tap(find.text(lDe.recoveryExhaustedAction));
        await tester.pumpAndSettle();

        expect(
          navTargets,
          ['advanced'],
          reason:
              'Action callback must request the advanced settings section '
              'so the user lands on the Factory-Reset row.',
        );

        // Drain the toast's 8s auto-dismiss timer so no Timer outlives
        // the test — tapping the action dismisses the overlay but the
        // delayed-dismiss `Future.delayed` is still pending.
        await tester.pumpAndSettle(const Duration(seconds: 9));
      },
    );

    testWidgets('abiInfo: renders passive info toast with no action button', (
      tester,
    ) async {
      var unexpectedNav = 0;

      await tester.pumpWidget(
        makeTestable(
          _RecoveryHarness(
            kind: RecoveryToastKind.abiInfo,
            openSettings: (_) => unexpectedNav++,
          ),
          locale: const Locale('de'),
        ),
      );

      await tester.tap(find.text('fire-recovery-toast'));
      await tester.pumpAndSettle();

      expect(find.text(lDe.modelAbiInfoToast), findsOneWidget);
      // No action label appears anywhere in the toast.
      expect(find.text(lDe.recoveryExhaustedAction), findsNothing);
      expect(unexpectedNav, 0);

      // Drain the toast's 5s auto-dismiss timer so no Timer outlives
      // the test.
      await tester.pumpAndSettle(const Duration(seconds: 6));
    });

    testWidgets('exhausted (en locale): English copy matches the ARB entry', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          _RecoveryHarness(
            kind: RecoveryToastKind.exhausted,
            openSettings: (_) {},
          ),
          locale: const Locale('en'),
        ),
      );

      await tester.tap(find.text('fire-recovery-toast'));
      await tester.pumpAndSettle();

      expect(find.text(lEn.recoveryExhaustedToast), findsOneWidget);
      expect(find.text(lEn.recoveryExhaustedAction), findsOneWidget);

      // Drain the toast's 8s auto-dismiss timer so no Timer outlives
      // the test.
      await tester.pumpAndSettle(const Duration(seconds: 9));
    });
  });
}
