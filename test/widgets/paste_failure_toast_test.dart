/// Tests for the paste-failure toast wired in `recording_behavior.dart`.
///
/// Mirrors the extracted-helper pattern from `recovery_toast_test.dart` /
/// `cpu_fallback_toast_test.dart`: [showPasteFailureToast] is exercised
/// through a minimal harness widget, so no app-shell/overlay bootstrapping
/// is required to prove which message (and action button, if any) a given
/// [PasteOutcome] renders.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/widgets/wp_button.dart';
import 'package:whispaste/services/paste/paster.dart';
import 'package:whispaste/widgets/recording_behavior.dart';

import '../fixtures/test_helpers.dart';

class _PasteFailureHarness extends StatelessWidget {
  const _PasteFailureHarness(
    this.outcome, {
    this.openAccessibilitySettings,
    this.resetEntryAndGrant,
    this.staleEntry = false,
  });

  final PasteOutcome outcome;
  final VoidCallback? openAccessibilitySettings;
  final VoidCallback? resetEntryAndGrant;
  final bool staleEntry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ElevatedButton(
        onPressed: () => showPasteFailureToast(
          context: context,
          l10n: L10n.of(context),
          outcome: outcome,
          openAccessibilitySettings: openAccessibilitySettings,
          resetEntryAndGrant: resetEntryAndGrant,
          staleEntry: staleEntry,
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
      expect(find.byType(WpButton), findsNothing);

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

  // ---------------------------------------------------------------------
  // permissionMissing — the toast must offer the SAME recovery the
  // failed-paste OS notification picks for the same failure. On the
  // live-probe macOS build that recovery clears the stale TCC entry first,
  // because a plain Settings deep-link can land the user on a toggle that is
  // already switched on, which reads as "nothing to do here".
  // ---------------------------------------------------------------------
  group('showPasteFailureToast — permissionMissing recovery', () {
    testWidgets(
      'without the reset seam it keeps the plain Settings action',
      (tester) async {
        await tester.pumpWidget(
          makeTestable(
            _PasteFailureHarness(
              PasteOutcome.permissionMissing,
              openAccessibilitySettings: () {},
            ),
            locale: const Locale('de'),
          ),
        );

        await tester.tap(find.text('fire-paste-failure-toast'));
        await tester.pumpAndSettle();

        expect(find.text(lDe.pasteFailureOpenSettings), findsOneWidget);
        expect(find.text(lDe.pasteCapabilityRepairButton), findsNothing);

        await tester.pumpAndSettle(const Duration(seconds: 6));
      },
      skip: !Platform.isMacOS,
    );

    testWidgets(
      'with the reset seam the action becomes the entry reset and firing it '
      'runs that recovery, not the Settings deep-link',
      (tester) async {
        var resetCalls = 0;
        var settingsCalls = 0;
        await tester.pumpWidget(
          makeTestable(
            _PasteFailureHarness(
              PasteOutcome.permissionMissing,
              openAccessibilitySettings: () => settingsCalls++,
              resetEntryAndGrant: () => resetCalls++,
            ),
            locale: const Locale('de'),
          ),
        );

        await tester.tap(find.text('fire-paste-failure-toast'));
        await tester.pumpAndSettle();

        expect(find.text(lDe.pasteFailureOpenSettings), findsNothing);
        // No in-process proof of a stale entry, so the copy stays generic —
        // a first-time user has no old entry to be told about.
        expect(find.text(lDe.pasteFailurePermissionMissing), findsOneWidget);

        await tester.tap(find.text(lDe.pasteCapabilityRepairButton));
        await tester.pumpAndSettle();
        expect(resetCalls, 1);
        expect(
          settingsCalls,
          0,
          reason:
              'The reset seam must replace the Settings deep-link here, not '
              'run alongside it.',
        );

        await tester.pumpAndSettle(const Duration(seconds: 6));
      },
      skip: !Platform.isMacOS,
    );

    testWidgets(
      'staleEntry swaps the copy to the reset hint — this process saw the '
      'grant happen and not take',
      (tester) async {
        await tester.pumpWidget(
          makeTestable(
            _PasteFailureHarness(
              PasteOutcome.permissionMissing,
              resetEntryAndGrant: () {},
              staleEntry: true,
            ),
            locale: const Locale('de'),
          ),
        );

        await tester.tap(find.text('fire-paste-failure-toast'));
        await tester.pumpAndSettle();

        expect(find.text(lDe.pasteCapabilityRepairHint), findsOneWidget);
        expect(find.text(lDe.pasteFailurePermissionMissing), findsNothing);

        await tester.pumpAndSettle(const Duration(seconds: 6));
      },
      skip: !Platform.isMacOS,
    );
  });
}
