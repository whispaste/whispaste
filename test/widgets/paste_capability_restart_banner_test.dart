/// Widget tests for [WpPasteCapabilityRestartBanner] and its wiring inside
/// [WpPasteCapabilityIndicator].
///
/// Covers the three external behaviours that matter:
///   1. The banner renders its copy and fires the injected restart callback.
///   2. The indicator surfaces the banner (and hides the grant CTA) exactly
///      when [PasteCapabilityNotifier.needsRestart] is `true`.
///   3. The indicator keeps the regular grant flow (no banner) for the
///      plain first-contact `permissionMissing` state.
///
/// The notifier is faked so no platform probes run; the requiredAction
/// resolver itself is unit-tested in
/// `test/services/paste/paste_capability_notifier_test.dart`.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/services/paste/paste_capability_notifier.dart';
import 'package:whispaste/services/paste/paster.dart';
import 'package:whispaste/widgets/paste_capability_indicator.dart';
import 'package:whispaste/widgets/paste_capability_restart_banner.dart';

import '../fixtures/test_helpers.dart';

/// Seeds a fixed [PasteCapabilityState] and never touches the platform.
class _FakePasteCapabilityNotifier extends PasteCapabilityNotifier {
  _FakePasteCapabilityNotifier(this._seed);

  final PasteCapabilityState _seed;

  @override
  PasteCapabilityState build() {
    // The banner under test is the cached-probe (Mac App Store) recovery —
    // the live-probe Developer-ID build never resolves `requiredAction` to
    // `restart`, because a relaunch cannot reveal a grant that polling would
    // not already have seen. See [PasteCapabilityNotifier
    // .usesCachedPermissionProbe].
    usesCachedPermissionProbe = true;
    return _seed;
  }

  @override
  Future<void> check({bool prompt = false}) async {}
}

const _mismatchState = PasteCapabilityState(
  capability: PasteCapability(
    status: PasteCapabilityStatus.permissionMissing,
    canPrompt: true,
  ),
  sentToOsGrantFlow: true,
  pollingPhase: PollingPhase.timedOut,
);

const _plainMissingState = PasteCapabilityState(
  capability: PasteCapability(
    status: PasteCapabilityStatus.permissionMissing,
    canPrompt: true,
  ),
);

/// Fresh process after a grant-driven restart that STILL reads missing: the
/// persisted marker is hydrated (`restartAttempted: true`) but this process
/// hasn't re-entered the grant flow (`sentToOsGrantFlow: false`), so the
/// resolver yields `grant` while the marker upgrades the copy to the honest
/// "restart didn't take" surface.
const _restartIneffectiveState = PasteCapabilityState(
  capability: PasteCapability(
    status: PasteCapabilityStatus.permissionMissing,
    canPrompt: true,
  ),
  restartAttempted: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late final L10n l10n;
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  group('WpPasteCapabilityRestartBanner', () {
    testWidgets('renders title, body and restart button; tap fires onRestart', (
      tester,
    ) async {
      var restartCalls = 0;
      await tester.pumpWidget(
        makeTestable(
          WpPasteCapabilityRestartBanner(onRestart: () => restartCalls++),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(l10n.pasteCapabilityRestartTitle), findsOneWidget);
      expect(find.text(l10n.pasteCapabilityRestartBody), findsOneWidget);
      expect(find.text(l10n.pasteCapabilityRestartButton), findsOneWidget);

      await tester.tap(find.text(l10n.pasteCapabilityRestartButton));
      await tester.pumpAndSettle();

      expect(restartCalls, 1);
    });
  });

  group('WpPasteCapabilityIndicator — restart banner wiring', () {
    // The indicator's macOS-only branches key off the real host platform;
    // these integration cases are only meaningful on a macOS test host.
    testWidgets(
      'needsRestart surfaces the banner and hides the grant CTA',
      skip: !Platform.isMacOS,
      (tester) async {
        await tester.pumpWidget(
          makeTestable(
            const WpPasteCapabilityIndicator(),
            locale: const Locale('en'),
            overrides: [
              pasteCapabilityNotifierProvider.overrideWith(
                () => _FakePasteCapabilityNotifier(_mismatchState),
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(WpPasteCapabilityRestartBanner), findsOneWidget);
        expect(find.text(l10n.pasteCapabilityRestartTitle), findsOneWidget);
        // Regular "not yet allowed" surface must be fully replaced.
        expect(find.text(l10n.pasteCapabilityGrantButton), findsNothing);
        expect(find.text(l10n.pasteCapabilityPermissionMissing), findsNothing);
        // Collapsed self-help stays reachable for the rare edge cases.
        expect(find.text(l10n.pasteCapabilityTroubleshoot), findsOneWidget);
      },
    );

    testWidgets(
      'plain permissionMissing keeps the grant flow and shows no banner',
      skip: !Platform.isMacOS,
      (tester) async {
        await tester.pumpWidget(
          makeTestable(
            const WpPasteCapabilityIndicator(),
            locale: const Locale('en'),
            overrides: [
              pasteCapabilityNotifierProvider.overrideWith(
                () => _FakePasteCapabilityNotifier(_plainMissingState),
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(WpPasteCapabilityRestartBanner), findsNothing);
        expect(
          find.text(l10n.pasteCapabilityPermissionMissing),
          findsOneWidget,
        );
        expect(find.text(l10n.pasteCapabilityGrantButton), findsOneWidget);
      },
    );

    testWidgets(
      'restartWasIneffective swaps the first-contact copy for the honest '
      '"restart did not take" copy while keeping the grant action',
      skip: !Platform.isMacOS,
      (tester) async {
        await tester.pumpWidget(
          makeTestable(
            const WpPasteCapabilityIndicator(),
            locale: const Locale('en'),
            overrides: [
              pasteCapabilityNotifierProvider.overrideWith(
                () => _FakePasteCapabilityNotifier(_restartIneffectiveState),
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();

        // Honest copy replaces the naive "not yet allowed" title the user
        // kept looping back to right after restarting.
        expect(
          find.text(l10n.pasteCapabilityRestartIneffectiveTitle),
          findsOneWidget,
        );
        expect(find.text(l10n.pasteCapabilityPermissionMissing), findsNothing);
        // The primary action stays grant (re-fires CGRequestPostEventAccess),
        // and this is NOT the sentToOsGrantFlow restart-banner surface.
        expect(find.text(l10n.pasteCapabilityGrantButton), findsOneWidget);
        expect(find.byType(WpPasteCapabilityRestartBanner), findsNothing);
      },
    );
  });
}
