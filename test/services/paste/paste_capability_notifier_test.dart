/// Unit tests for [PasteCapabilityNotifier].
///
/// Style mirrors `paster_test.dart`: hand-rolled fakes for the platform
/// dependencies (`Paster`, `DesktopPasteController`), Riverpod overrides
/// for DI. No mockito/build_runner required.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/services/desktop_paste/desktop_paste_controller.dart';
import 'package:whispaste/services/paste/paste_capability_notifier.dart';
import 'package:whispaste/services/paste/paster.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakePaster implements Paster {
  _FakePaster({
    PasteCapability initial = const PasteCapability(
      status: PasteCapabilityStatus.permissionMissing,
      canPrompt: true,
    ),
  }) : _next = initial;

  PasteCapability _next;
  final List<bool> calls = <bool>[];
  Completer<void>? _gate;

  set nextResult(PasteCapability cap) => _next = cap;

  /// If set, [checkCapability] awaits this completer before resolving. Used
  /// to test that [PasteCapabilityNotifier.check] does not stack concurrent
  /// calls (later) and to model the periodic-call ordering in polling tests.
  set gate(Completer<void>? c) => _gate = c;

  @override
  Future<PasteCapability> checkCapability({
    bool promptIfMissing = false,
  }) async {
    calls.add(promptIfMissing);
    final g = _gate;
    if (g != null) await g.future;
    return _next;
  }

  // Unused methods — checkCapability is the only Paster surface the notifier
  // touches.
  @override
  Future<void> prime() async {}

  @override
  Future<PasteOutcome> paste(String text, PasteOptions options) async =>
      PasteOutcome.platformUnavailable;
}

class _FakeRepairController implements DesktopPasteController {
  TccRepairResult repairResult = const TccRepairResult(
    accessibilityCleared: 0,
    appleEventsCleared: 0,
  );
  int repairCalls = 0;

  /// Seeded outcome for [diagnosticPaste]. Tests rebind it per scenario to
  /// exercise each [TestPasteOutcome] variant.
  TestPasteOutcome diagnosticOutcome = const TestPasteOutcomeSuccess();

  /// Captures every demoText the notifier forwards to the controller — proves
  /// the wrapper does not silently re-key the argument.
  final List<String> diagnosticCalls = <String>[];

  @override
  Future<TccRepairResult> repairTccEntries() async {
    repairCalls++;
    return repairResult;
  }

  @override
  Future<TestPasteOutcome> diagnosticPaste(String demoText) async {
    diagnosticCalls.add(demoText);
    return diagnosticOutcome;
  }

  // Unused
  @override
  Future<bool> capturePasteTarget() async => false;
  @override
  Future<NativeCapabilityResult> checkCapability({
    bool promptIfMissing = false,
  }) async =>
      const NativeCapabilityResult(status: NativeCapabilityStatus.unsupported);
  @override
  Future<String?> getTargetBundleId() async => null;
  @override
  Future<NativePasteResult> pasteClipboard({required Duration delay}) async =>
      const NativePasteResult(status: NativePasteStatus.unknown);
  @override
  Future<void> dispose() async {}
}

ProviderContainer _container({
  Paster? paster,
  DesktopPasteController? controller,
}) {
  return ProviderContainer(
    overrides: [
      pasterProvider.overrideWithValue(paster),
      desktopPasteControllerProvider.overrideWithValue(controller),
    ],
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PasteCapabilityNotifier — check()', () {
    test(
      'check(prompt: false) calls Paster.checkCapability(promptIfMissing: false) once '
      'and state mirrors the result',
      () async {
        final paster = _FakePaster(
          initial: const PasteCapability(status: PasteCapabilityStatus.ready),
        );
        final container = _container(paster: paster);
        addTearDown(container.dispose);

        final notifier = container.read(
          pasteCapabilityNotifierProvider.notifier,
        );
        await notifier.check();

        expect(paster.calls, [false]);
        final state = container.read(pasteCapabilityNotifierProvider);
        expect(state.capability?.status, PasteCapabilityStatus.ready);
      },
    );

    test(
      'check(prompt: true) with permissionMissing result sets hadFailedGrantAttempt = true',
      () async {
        final paster = _FakePaster(
          initial: const PasteCapability(
            status: PasteCapabilityStatus.permissionMissing,
            canPrompt: true,
          ),
        );
        final container = _container(paster: paster);
        addTearDown(container.dispose);

        final notifier = container.read(
          pasteCapabilityNotifierProvider.notifier,
        );
        await notifier.check(prompt: true);

        expect(paster.calls, [true]);
        final state = container.read(pasteCapabilityNotifierProvider);
        expect(
          state.capability?.status,
          PasteCapabilityStatus.permissionMissing,
        );
        expect(state.hadFailedGrantAttempt, isTrue);
      },
    );

    test(
      'check(prompt: true) with ready result leaves hadFailedGrantAttempt = false',
      () async {
        final paster = _FakePaster(
          initial: const PasteCapability(status: PasteCapabilityStatus.ready),
        );
        final container = _container(paster: paster);
        addTearDown(container.dispose);

        final notifier = container.read(
          pasteCapabilityNotifierProvider.notifier,
        );
        await notifier.check(prompt: true);

        final state = container.read(pasteCapabilityNotifierProvider);
        expect(state.capability?.status, PasteCapabilityStatus.ready);
        expect(state.hadFailedGrantAttempt, isFalse);
      },
    );

    test(
      'check without paster surface yields unsupported capability',
      () async {
        final container = _container(paster: null);
        addTearDown(container.dispose);

        final notifier = container.read(
          pasteCapabilityNotifierProvider.notifier,
        );
        await notifier.check();

        final state = container.read(pasteCapabilityNotifierProvider);
        expect(state.capability?.status, PasteCapabilityStatus.unsupported);
      },
    );
  });

  group('PasteCapabilityNotifier — pollingPhase', () {
    test('initial state is PollingPhase.idle', () async {
      final paster = _FakePaster();
      final container = _container(paster: paster);
      addTearDown(container.dispose);

      final state = container.read(pasteCapabilityNotifierProvider);
      expect(state.pollingPhase, PollingPhase.idle);
    });

    test('startPolling sets pollingPhase to awaitingGrant', () async {
      final paster = _FakePaster();
      final container = _container(paster: paster);
      addTearDown(container.dispose);

      final notifier = container.read(pasteCapabilityNotifierProvider.notifier);
      notifier.startPolling(
        interval: const Duration(seconds: 1),
        timeout: const Duration(seconds: 30),
      );

      final state = container.read(pasteCapabilityNotifierProvider);
      expect(state.pollingPhase, PollingPhase.awaitingGrant);
      expect(notifier.isPolling, isTrue);

      // Clean up the active timer.
      notifier.stopPolling();
    });

    test(
      'successful poll (capability ready) sets pollingPhase to succeeded and stops timer',
      () async {
        final paster = _FakePaster(
          initial: const PasteCapability(status: PasteCapabilityStatus.ready),
        );
        final container = _container(paster: paster);
        addTearDown(container.dispose);

        final notifier = container.read(
          pasteCapabilityNotifierProvider.notifier,
        );
        notifier.startPolling(
          interval: const Duration(milliseconds: 20),
          timeout: const Duration(seconds: 5),
        );
        // Let the first tick observe `ready`.
        await Future<void>.delayed(const Duration(milliseconds: 80));

        expect(notifier.isPolling, isFalse);
        final state = container.read(pasteCapabilityNotifierProvider);
        expect(state.pollingPhase, PollingPhase.succeeded);
      },
    );

    test('timeout sets pollingPhase to timedOut', () async {
      final paster = _FakePaster(
        initial: const PasteCapability(
          status: PasteCapabilityStatus.permissionMissing,
          canPrompt: true,
        ),
      );
      final container = _container(paster: paster);
      addTearDown(container.dispose);

      final notifier = container.read(pasteCapabilityNotifierProvider.notifier);
      notifier.startPolling(
        interval: const Duration(milliseconds: 20),
        timeout: const Duration(milliseconds: 60),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(notifier.isPolling, isFalse);
      final state = container.read(pasteCapabilityNotifierProvider);
      expect(state.pollingPhase, PollingPhase.timedOut);
    });

    test('stopPolling sets pollingPhase to idle', () async {
      final paster = _FakePaster(
        initial: const PasteCapability(
          status: PasteCapabilityStatus.permissionMissing,
          canPrompt: true,
        ),
      );
      final container = _container(paster: paster);
      addTearDown(container.dispose);

      final notifier = container.read(pasteCapabilityNotifierProvider.notifier);
      notifier.startPolling(
        interval: const Duration(milliseconds: 20),
        timeout: const Duration(seconds: 5),
      );
      expect(
        container.read(pasteCapabilityNotifierProvider).pollingPhase,
        PollingPhase.awaitingGrant,
      );

      notifier.stopPolling();
      expect(
        container.read(pasteCapabilityNotifierProvider).pollingPhase,
        PollingPhase.idle,
      );
    });

    test(
      'isPolling getter returns true iff pollingPhase == awaitingGrant',
      () async {
        final paster = _FakePaster();
        final container = _container(paster: paster);
        addTearDown(container.dispose);

        final notifier = container.read(
          pasteCapabilityNotifierProvider.notifier,
        );
        expect(notifier.isPolling, isFalse);

        notifier.startPolling(
          interval: const Duration(seconds: 1),
          timeout: const Duration(seconds: 30),
        );
        expect(notifier.isPolling, isTrue);

        notifier.stopPolling();
        expect(notifier.isPolling, isFalse);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // suspectedTccMismatch — truth table.
  //
  // The getter is a pure function of three state fields:
  //   - hadFailedGrantAttempt (sticky)
  //   - capability?.status == permissionMissing
  //   - pollingPhase == timedOut
  // It is `true` exactly when all three are simultaneously true, and `false`
  // otherwise. The tests below cover the all-true case plus each single-field
  // falsification so the conjunction is exercised end-to-end.
  // ---------------------------------------------------------------------------
  group('PasteCapabilityNotifier — suspectedTccMismatch', () {
    // Lightweight harness: build a notifier and force-mutate state through
    // the public surface. We can't write to `state` directly from a test, so
    // we use the timeout machinery + `check()` to drive the relevant fields
    // — same path the real macOS flow takes.
    Future<PasteCapabilityNotifier> driveTo({
      required ProviderContainer container,
      required _FakePaster paster,
      required bool hadFailedGrantAttempt,
      required PasteCapabilityStatus capabilityStatus,
      required PollingPhase pollingPhase,
    }) async {
      final notifier = container.read(pasteCapabilityNotifierProvider.notifier);
      // Drive `hadFailedGrantAttempt` via a prompted check that comes back
      // as permissionMissing — that's the only public way to flip it.
      if (hadFailedGrantAttempt) {
        paster.nextResult = const PasteCapability(
          status: PasteCapabilityStatus.permissionMissing,
          canPrompt: true,
        );
        await notifier.check(prompt: true);
      }
      // Then drive the capability to the desired terminal status.
      paster.nextResult = PasteCapability(status: capabilityStatus);
      await notifier.check();
      // Finally drive `pollingPhase` via the timer machinery. We use a
      // short timeout to reach `timedOut` quickly when needed, and skip
      // polling entirely for the `idle` case.
      switch (pollingPhase) {
        case PollingPhase.idle:
          // Already idle — nothing to do.
          break;
        case PollingPhase.awaitingGrant:
          notifier.startPolling(
            interval: const Duration(seconds: 10),
            timeout: const Duration(seconds: 10),
          );
          break;
        case PollingPhase.succeeded:
          // Setting the next result to `ready` makes the first tick
          // self-stop with `succeeded`.
          paster.nextResult = const PasteCapability(
            status: PasteCapabilityStatus.ready,
          );
          notifier.startPolling(
            interval: const Duration(milliseconds: 10),
            timeout: const Duration(seconds: 5),
          );
          await Future<void>.delayed(const Duration(milliseconds: 60));
          // Restore the desired terminal capability after self-stop, since
          // the `succeeded` self-stop will have overwritten it.
          paster.nextResult = PasteCapability(status: capabilityStatus);
          await notifier.check();
          break;
        case PollingPhase.timedOut:
          notifier.startPolling(
            interval: const Duration(seconds: 5),
            timeout: const Duration(milliseconds: 20),
          );
          await Future<void>.delayed(const Duration(milliseconds: 80));
          // Restore the desired terminal capability after the timeout self-
          // stop has overwritten it via the last poll tick (if any).
          paster.nextResult = PasteCapability(status: capabilityStatus);
          await notifier.check();
          break;
      }
      return notifier;
    }

    test('all three conditions true → suspectedTccMismatch is true', () async {
      final paster = _FakePaster();
      final container = _container(paster: paster);
      addTearDown(container.dispose);

      final notifier = await driveTo(
        container: container,
        paster: paster,
        hadFailedGrantAttempt: true,
        capabilityStatus: PasteCapabilityStatus.permissionMissing,
        pollingPhase: PollingPhase.timedOut,
      );

      expect(notifier.suspectedTccMismatch, isTrue);
    });

    test(
      'hadFailedGrantAttempt == false → suspectedTccMismatch is false',
      () async {
        final paster = _FakePaster();
        final container = _container(paster: paster);
        addTearDown(container.dispose);

        final notifier = await driveTo(
          container: container,
          paster: paster,
          hadFailedGrantAttempt: false,
          capabilityStatus: PasteCapabilityStatus.permissionMissing,
          pollingPhase: PollingPhase.timedOut,
        );

        expect(notifier.suspectedTccMismatch, isFalse);
      },
    );

    test(
      'capability status != permissionMissing → suspectedTccMismatch is false',
      () async {
        final paster = _FakePaster();
        final container = _container(paster: paster);
        addTearDown(container.dispose);

        final notifier = await driveTo(
          container: container,
          paster: paster,
          hadFailedGrantAttempt: true,
          // Even `ready` (the happy path) must not light up the banner.
          capabilityStatus: PasteCapabilityStatus.ready,
          pollingPhase: PollingPhase.timedOut,
        );

        expect(notifier.suspectedTccMismatch, isFalse);
      },
    );

    test('pollingPhase != timedOut → suspectedTccMismatch is false', () async {
      final paster = _FakePaster();
      final container = _container(paster: paster);
      addTearDown(container.dispose);

      final notifier = await driveTo(
        container: container,
        paster: paster,
        hadFailedGrantAttempt: true,
        capabilityStatus: PasteCapabilityStatus.permissionMissing,
        pollingPhase: PollingPhase.awaitingGrant,
      );

      expect(notifier.suspectedTccMismatch, isFalse);
      notifier.stopPolling();
    });

    test('pollingPhase == succeeded with the other two true → '
        'suspectedTccMismatch is false', () async {
      final paster = _FakePaster();
      final container = _container(paster: paster);
      addTearDown(container.dispose);

      final notifier = await driveTo(
        container: container,
        paster: paster,
        hadFailedGrantAttempt: true,
        capabilityStatus: PasteCapabilityStatus.permissionMissing,
        pollingPhase: PollingPhase.succeeded,
      );

      expect(notifier.suspectedTccMismatch, isFalse);
    });

    test('initial state → suspectedTccMismatch is false', () async {
      final paster = _FakePaster();
      final container = _container(paster: paster);
      addTearDown(container.dispose);

      final notifier = container.read(pasteCapabilityNotifierProvider.notifier);
      expect(notifier.suspectedTccMismatch, isFalse);
    });
  });

  group('PasteCapabilityNotifier — polling', () {
    test(
      'startPolling calls check periodically until ready, then stops itself',
      () async {
        final paster = _FakePaster(
          initial: const PasteCapability(
            status: PasteCapabilityStatus.permissionMissing,
            canPrompt: true,
          ),
        );
        final container = _container(paster: paster);
        addTearDown(container.dispose);

        final notifier = container.read(
          pasteCapabilityNotifierProvider.notifier,
        );

        notifier.startPolling(
          interval: const Duration(milliseconds: 20),
          timeout: const Duration(seconds: 5),
        );

        // Let two polling intervals pass while still permissionMissing.
        await Future<void>.delayed(const Duration(milliseconds: 70));
        expect(paster.calls.length, greaterThanOrEqualTo(2));
        expect(notifier.isPolling, isTrue);

        // Flip to ready and let the next tick observe it.
        paster.nextResult = const PasteCapability(
          status: PasteCapabilityStatus.ready,
        );
        await Future<void>.delayed(const Duration(milliseconds: 80));

        expect(notifier.isPolling, isFalse);
        final state = container.read(pasteCapabilityNotifierProvider);
        expect(state.capability?.status, PasteCapabilityStatus.ready);

        // No further calls after self-stop.
        final callsAfterStop = paster.calls.length;
        await Future<void>.delayed(const Duration(milliseconds: 80));
        expect(paster.calls.length, callsAfterStop);
      },
    );

    test('startPolling self-stops after timeout even if never ready', () async {
      final paster = _FakePaster(
        initial: const PasteCapability(
          status: PasteCapabilityStatus.permissionMissing,
          canPrompt: true,
        ),
      );
      final container = _container(paster: paster);
      addTearDown(container.dispose);

      final notifier = container.read(pasteCapabilityNotifierProvider.notifier);

      notifier.startPolling(
        interval: const Duration(milliseconds: 20),
        timeout: const Duration(milliseconds: 80),
      );

      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(notifier.isPolling, isFalse);

      // No further calls after timeout.
      final callsAfterTimeout = paster.calls.length;
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(paster.calls.length, callsAfterTimeout);
    });

    test('stopPolling is idempotent and safe to call repeatedly', () async {
      final paster = _FakePaster(
        initial: const PasteCapability(
          status: PasteCapabilityStatus.permissionMissing,
          canPrompt: true,
        ),
      );
      final container = _container(paster: paster);
      addTearDown(container.dispose);

      final notifier = container.read(pasteCapabilityNotifierProvider.notifier);

      // Idempotent before any startPolling call.
      notifier.stopPolling();
      notifier.stopPolling();
      expect(notifier.isPolling, isFalse);

      // Idempotent after startPolling.
      notifier.startPolling(
        interval: const Duration(milliseconds: 20),
        timeout: const Duration(seconds: 5),
      );
      notifier.stopPolling();
      notifier.stopPolling();
      expect(notifier.isPolling, isFalse);

      final callsAfterStop = paster.calls.length;
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(paster.calls.length, callsAfterStop);
    });
  });

  group('PasteCapabilityNotifier — runDiagnosticPaste()', () {
    test(
      'delegates to controller with the given demoText and returns success',
      () async {
        final controller = _FakeRepairController()
          ..diagnosticOutcome = const TestPasteOutcomeSuccess();
        final paster = _FakePaster();
        final container = _container(paster: paster, controller: controller);
        addTearDown(container.dispose);

        final notifier = container.read(
          pasteCapabilityNotifierProvider.notifier,
        );
        final outcome = await notifier.runDiagnosticPaste('WhisPaste demo');

        expect(controller.diagnosticCalls, ['WhisPaste demo']);
        expect(outcome, isA<TestPasteOutcomeSuccess>());
      },
    );

    test('propagates noFrontmost outcome 1:1', () async {
      final controller = _FakeRepairController()
        ..diagnosticOutcome = const TestPasteOutcomeNoFrontmost();
      final paster = _FakePaster();
      final container = _container(paster: paster, controller: controller);
      addTearDown(container.dispose);

      final notifier = container.read(pasteCapabilityNotifierProvider.notifier);
      final outcome = await notifier.runDiagnosticPaste('demo');

      expect(outcome, isA<TestPasteOutcomeNoFrontmost>());
    });

    test('propagates failure outcome with reason', () async {
      final controller = _FakeRepairController()
        ..diagnosticOutcome = const TestPasteOutcomeFailure('not_trusted');
      final paster = _FakePaster();
      final container = _container(paster: paster, controller: controller);
      addTearDown(container.dispose);

      final notifier = container.read(pasteCapabilityNotifierProvider.notifier);
      final outcome = await notifier.runDiagnosticPaste('demo');

      expect(outcome, isA<TestPasteOutcomeFailure>());
      expect((outcome as TestPasteOutcomeFailure).reason, 'not_trusted');
    });

    test('propagates unsupported outcome', () async {
      final controller = _FakeRepairController()
        ..diagnosticOutcome = const TestPasteOutcomeUnsupported();
      final paster = _FakePaster();
      final container = _container(paster: paster, controller: controller);
      addTearDown(container.dispose);

      final notifier = container.read(pasteCapabilityNotifierProvider.notifier);
      final outcome = await notifier.runDiagnosticPaste('demo');

      expect(outcome, isA<TestPasteOutcomeUnsupported>());
    });

    test('returns unsupported when no controller is registered', () async {
      final paster = _FakePaster();
      final container = _container(paster: paster, controller: null);
      addTearDown(container.dispose);

      final notifier = container.read(pasteCapabilityNotifierProvider.notifier);
      final outcome = await notifier.runDiagnosticPaste('demo');

      expect(outcome, isA<TestPasteOutcomeUnsupported>());
    });
  });

  group('PasteCapabilityNotifier — repair()', () {
    test(
      'repair delegates to DesktopPasteController.repairTccEntries and returns the result',
      () async {
        final controller = _FakeRepairController()
          ..repairResult = const TccRepairResult(
            accessibilityCleared: 2,
            appleEventsCleared: 1,
          );
        final paster = _FakePaster();
        final container = _container(paster: paster, controller: controller);
        addTearDown(container.dispose);

        final notifier = container.read(
          pasteCapabilityNotifierProvider.notifier,
        );
        final result = await notifier.repair();

        expect(controller.repairCalls, 1);
        expect(result.accessibilityCleared, 2);
        expect(result.appleEventsCleared, 1);
        expect(result.isSupported, isTrue);
      },
    );

    test(
      'repair returns unsupported result when no controller is available',
      () async {
        final paster = _FakePaster();
        final container = _container(paster: paster, controller: null);
        addTearDown(container.dispose);

        final notifier = container.read(
          pasteCapabilityNotifierProvider.notifier,
        );
        final result = await notifier.repair();

        expect(result.isSupported, isFalse);
      },
    );
  });
}
