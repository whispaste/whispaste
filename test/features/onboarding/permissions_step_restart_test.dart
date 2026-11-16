/// What the paste row of the onboarding permissions page triggers (#420, #431).
///
/// The Mac App Store build may read the paste permission only at launch, but
/// it cannot see the switch either: the restart is a second way once the user
/// is back from System Settings, never the only one. The live-probe build
/// keeps asking.
library;

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/features/onboarding/steps/permissions_step.dart';
import 'package:whispaste/services/paste/paste_capability_notifier.dart';
import 'package:whispaste/services/paste/paster.dart';
import 'package:whispaste/services/permissions/mic_permission_notifier.dart';

import '../../fixtures/test_helpers.dart';

class _GrantedMic implements MicPermissionChecker {
  @override
  Future<bool> check({required bool request}) async => true;
}

/// Paste fake: permission missing, user already sent to System Settings.
class _SentPaste extends PasteCapabilityNotifier {
  _SentPaste({required bool cached, required this.back}) {
    usesCachedPermissionProbe = cached;
  }

  final bool back;
  int restarts = 0;
  int grants = 0;

  @override
  PasteCapabilityState build() => PasteCapabilityState(
    capability: const PasteCapability(
      status: PasteCapabilityStatus.permissionMissing,
    ),
    sentToOsGrantFlow: true,
    pollingPhase: back ? PollingPhase.idle : PollingPhase.awaitingGrant,
    backFromOsGrantFlow: back,
  );

  @override
  Future<void> check({bool prompt = false}) async {}

  @override
  Future<void> requestGrant({
    Duration pollInterval = const Duration(seconds: 1),
    Duration pollTimeout = const Duration(seconds: 30),
  }) async => grants++;

  @override
  Future<void> restartForGrant() async => restarts++;

  @override
  void startPolling({
    Duration interval = const Duration(seconds: 1),
    Duration timeout = const Duration(seconds: 30),
  }) {}

  @override
  void stopPolling() {}
}

Future<void> _pump(
  WidgetTester tester,
  _SentPaste paste, {
  ValueChanged<bool>? onPasteDeclined,
}) async {
  await tester.pumpWidget(
    makeTestable(
      SingleChildScrollView(
        child: PermissionsStep(onNext: () {}, onPasteDeclined: onPasteDeclined),
      ),
      size: const Size(1280, 800),
      overrides: [
        micPermissionCheckerProvider.overrideWithValue(_GrantedMic()),
        pasteCapabilityNotifierProvider.overrideWith(() => paste),
      ],
    ),
  );
  await tester.pump();
}

Future<void> _onMac(Future<void> Function() body) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

void main() {
  const allow = ValueKey('onboarding-permissions-paste-allow');
  const restart = ValueKey('onboarding-permissions-paste-restart');

  testWidgets('Mac App Store build: no restart while the user has not come '
      'back from System Settings', (tester) async {
    await _onMac(() async {
      final paste = _SentPaste(cached: true, back: false);
      await _pump(tester, paste);

      expect(find.byKey(restart), findsNothing);
      await tester.tap(find.byKey(allow));
      await tester.pump();

      expect(paste.grants, 1);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('Mac App Store build: back from System Settings, the restart is '
      'a second way next to asking again', (tester) async {
    await _onMac(() async {
      final paste = _SentPaste(cached: true, back: true);
      await _pump(tester, paste);

      expect(find.byKey(allow), findsOneWidget);
      await tester.tap(find.byKey(restart));
      await tester.pump();

      expect(paste.restarts, 1);
      expect(paste.grants, 0);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('live-probe build: the paste row asks for the grant again', (
    tester,
  ) async {
    await _onMac(() async {
      final paste = _SentPaste(cached: false, back: false);
      await _pump(tester, paste);

      expect(find.byKey(restart), findsNothing);
      await tester.tap(find.byKey(allow));
      await tester.pump();

      expect(paste.grants, 1);
      expect(paste.restarts, 0);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('going on without the permission reports the decline', (
    tester,
  ) async {
    await _onMac(() async {
      final declines = <bool>[];
      final paste = _SentPaste(cached: true, back: false);
      await _pump(tester, paste, onPasteDeclined: declines.add);

      await tester.tap(find.byKey(allow));
      await tester.pump();

      expect(declines, [false]);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
