/// Widget tests for [PasteCapabilityRestartBanner] and its wiring inside
/// [PasteCapabilityIndicator].
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
  PasteCapabilityState build() => _seed;

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late final L10n l10n;
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  group('PasteCapabilityRestartBanner', () {
    testWidgets('renders title, body and restart button; tap fires onRestart', (
      tester,
    ) async {
      var restartCalls = 0;
      await tester.pumpWidget(
        makeTestable(
          PasteCapabilityRestartBanner(onRestart: () => restartCalls++),
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

  group('PasteCapabilityIndicator — restart banner wiring', () {
    // The indicator's macOS-only branches key off the real host platform;
    // these integration cases are only meaningful on a macOS test host.
    testWidgets(
      'needsRestart surfaces the banner and hides the grant CTA',
      skip: !Platform.isMacOS,
      (tester) async {
        await tester.pumpWidget(
          makeTestable(
            const PasteCapabilityIndicator(),
            locale: const Locale('en'),
            overrides: [
              pasteCapabilityNotifierProvider.overrideWith(
                () => _FakePasteCapabilityNotifier(_mismatchState),
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(PasteCapabilityRestartBanner), findsOneWidget);
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
            const PasteCapabilityIndicator(),
            locale: const Locale('en'),
            overrides: [
              pasteCapabilityNotifierProvider.overrideWith(
                () => _FakePasteCapabilityNotifier(_plainMissingState),
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(PasteCapabilityRestartBanner), findsNothing);
        expect(
          find.text(l10n.pasteCapabilityPermissionMissing),
          findsOneWidget,
        );
        expect(find.text(l10n.pasteCapabilityGrantButton), findsOneWidget);
      },
    );
  });
}
