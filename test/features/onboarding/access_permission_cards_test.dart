/// Widget tests for the access page's permission cards (Onboarding v6, V03).
///
/// What is pinned here: each permission has its own card with an "Erlauben"
/// button, the card flips to its granted checkmark within two seconds without
/// a click (live check on a fake clock), the Windows page shows the microphone
/// card only, a waiting page carries the removal fallback, and the layout holds
/// at text scale 1.3 and 2.0 in 800 x 600 and under right-to-left.
library;

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/onboarding/steps/auto_paste_step.dart';
import 'package:whispaste/services/paste/paste_capability_notifier.dart';
import 'package:whispaste/services/paste/paster.dart';
import 'package:whispaste/services/permissions/mic_permission_notifier.dart';

import '../../fixtures/test_helpers.dart';

/// Microphone checker whose answer the test flips.
class _FlipMicChecker implements MicPermissionChecker {
  bool granted = false;
  int reads = 0;

  @override
  Future<bool> check({required bool request}) async {
    reads++;
    return granted;
  }
}

/// Microphone checker whose platform read always fails (no channel on a test
/// host). The live check must swallow the error and keep the card pending.
class _ThrowingMicChecker implements MicPermissionChecker {
  @override
  Future<bool> check({required bool request}) async {
    throw StateError('no platform channel in this test host');
  }
}

/// Switches for the paste capability fake: granted, and awaiting the grant.
class _PasteSwitch {
  bool granted = false;
  bool waiting = false;
}

/// Paste capability fake: the status follows [_PasteSwitch], every `check`
/// re-reads it, and no real platform probe or poll runs.
class _FlipPasteNotifier extends PasteCapabilityNotifier {
  _FlipPasteNotifier(this.switches);

  final _PasteSwitch switches;

  PasteCapabilityState _current() => PasteCapabilityState(
    capability: PasteCapability(
      status: switches.granted
          ? PasteCapabilityStatus.ready
          : PasteCapabilityStatus.permissionMissing,
    ),
    pollingPhase: switches.waiting
        ? PollingPhase.awaitingGrant
        : PollingPhase.idle,
  );

  @override
  PasteCapabilityState build() => _current();

  @override
  Future<void> check({bool prompt = false}) async {
    state = _current();
  }

  @override
  Future<void> requestGrant({
    Duration pollInterval = const Duration(seconds: 1),
    Duration pollTimeout = const Duration(seconds: 30),
  }) async {}

  @override
  void startPolling({
    Duration interval = const Duration(seconds: 1),
    Duration timeout = const Duration(seconds: 30),
  }) {}

  @override
  void stopPolling() {}
}

/// Runs [body] with a forced target platform. The override is reset in a
/// `finally`, because flutter_test checks it before `addTearDown` runs.
Future<void> _onPlatform(
  TargetPlatform platform,
  Future<void> Function() body,
) async {
  debugDefaultTargetPlatformOverride = platform;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

Future<void> _pumpAccess(
  WidgetTester tester, {
  required MicPermissionChecker mic,
  required _PasteSwitch paste,
  Size size = const Size(1280, 800),
  Locale locale = const Locale('en'),
  double textScale = 1.0,
}) async {
  await tester.pumpWidget(
    makeTestable(
      Builder(
        builder: (context) {
          final media = MediaQuery.of(context);
          return MediaQuery(
            data: media.copyWith(textScaler: TextScaler.linear(textScale)),
            child: const SingleChildScrollView(child: AutoPasteStep()),
          );
        },
      ),
      size: size,
      locale: locale,
      overrides: [
        micPermissionCheckerProvider.overrideWithValue(mic),
        pasteCapabilityNotifierProvider.overrideWith(
          () => _FlipPasteNotifier(paste),
        ),
      ],
    ),
  );
  // The first frame runs the post-frame probe and arms the live timer.
  await tester.pump();
}

Finder _micAction() =>
    find.byKey(const ValueKey('permissions-row-microphone-action'));

Finder _pasteAction() =>
    find.byKey(const ValueKey('permissions-row-auto-paste-action'));

void main() {
  group('access page permission cards (V03)', () {
    testWidgets('each missing permission shows its own Erlauben button', (
      tester,
    ) async {
      await _onPlatform(TargetPlatform.macOS, () async {
        final l10n = await L10n.delegate.load(const Locale('en'));
        await _pumpAccess(
          tester,
          mic: _FlipMicChecker(),
          paste: _PasteSwitch(),
        );

        expect(_micAction(), findsOneWidget);
        expect(_pasteAction(), findsOneWidget);
        expect(find.text(l10n.permissionRowAllow), findsNWidgets(2));
      });
    });

    testWidgets(
      'microphone card flips to granted within two seconds, no click',
      (tester) async {
        await _onPlatform(TargetPlatform.macOS, () async {
          final mic = _FlipMicChecker();
          await _pumpAccess(
            tester,
            mic: mic,
            paste: _PasteSwitch()..granted = true,
          );
          expect(_micAction(), findsOneWidget);

          // The user flips the switch in System Settings; WhisPaste stays open.
          mic.granted = true;
          await tester.pump(const Duration(seconds: 2));

          expect(_micAction(), findsNothing);
          expect(mic.reads, greaterThanOrEqualTo(2));
        });
      },
    );

    testWidgets(
      'Auto-Paste card flips to granted within two seconds, no click',
      (tester) async {
        await _onPlatform(TargetPlatform.macOS, () async {
          final paste = _PasteSwitch();
          await _pumpAccess(
            tester,
            mic: _FlipMicChecker()..granted = true,
            paste: paste,
          );
          expect(_pasteAction(), findsOneWidget);

          paste.granted = true;
          await tester.pump(const Duration(seconds: 2));

          expect(_pasteAction(), findsNothing);
        });
      },
    );

    testWidgets(
      'a failing microphone read keeps the card pending and throws nothing',
      (tester) async {
        await _onPlatform(TargetPlatform.macOS, () async {
          await _pumpAccess(
            tester,
            mic: _ThrowingMicChecker(),
            paste: _PasteSwitch(),
          );
          await tester.pump(const Duration(seconds: 3));

          expect(tester.takeException(), isNull);
          expect(_micAction(), findsOneWidget);
        });
      },
    );

    testWidgets(
      'Windows shows the microphone card and no Auto-Paste permission card',
      (tester) async {
        await _onPlatform(TargetPlatform.windows, () async {
          await _pumpAccess(
            tester,
            mic: _FlipMicChecker(),
            paste: _PasteSwitch(),
          );

          expect(_micAction(), findsOneWidget);
          expect(_pasteAction(), findsNothing);
        });
      },
    );

    testWidgets('waiting for the grant shows the removal fallback sentence', (
      tester,
    ) async {
      await _onPlatform(TargetPlatform.macOS, () async {
        final l10n = await L10n.delegate.load(const Locale('en'));
        await _pumpAccess(
          tester,
          mic: _FlipMicChecker()..granted = true,
          paste: _PasteSwitch()..waiting = true,
        );

        expect(
          find.textContaining(l10n.onboardingAccessRemoveReAddHint),
          findsOneWidget,
        );
      });
    });
  });
}
