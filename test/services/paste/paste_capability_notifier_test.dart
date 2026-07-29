/// Unit tests for [PasteCapabilityNotifier].
///
/// Style mirrors `paster_test.dart`: hand-rolled fakes for the platform
/// dependencies (`Paster`, `DesktopPasteController`), Riverpod overrides
/// for DI. No mockito/build_runner required.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

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

  @override
  Future<PasteOutcome> typeText(String text, PasteOptions options) async =>
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
  Future<NativePasteResult> typeText(
    String text, {
    required Duration delay,
  }) async => const NativePasteResult(status: NativePasteStatus.unknown);
  @override
  Future<void> dispose() async {}
}

/// Records every URL [requestGrant]/[openAccessibilitySettings] hand off to
/// the OS, so tests can assert whether the Settings deep-link fired without
/// touching a real platform channel.
class _FakeUrlLauncher extends UrlLauncherPlatform
    with MockPlatformInterfaceMixin {
  final List<String> launchedUrls = <String>[];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launchedUrls.add(url);
    return true;
  }
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

    test('check(prompt: true) with permissionMissing does NOT set '
        'sentToOsGrantFlow — probing never owns the handoff bit', () async {
      final paster = _FakePaster(
        initial: const PasteCapability(
          status: PasteCapabilityStatus.permissionMissing,
          canPrompt: true,
        ),
      );
      final container = _container(paster: paster);
      addTearDown(container.dispose);

      final notifier = container.read(pasteCapabilityNotifierProvider.notifier);
      await notifier.check(prompt: true);

      expect(paster.calls, [true]);
      final state = container.read(pasteCapabilityNotifierProvider);
      expect(state.capability?.status, PasteCapabilityStatus.permissionMissing);
      expect(
        state.sentToOsGrantFlow,
        isFalse,
        reason:
            'Only requestGrant/openAccessibilitySettings own the handoff '
            'bit — a bare probe must not flip it.',
      );
    });

    test('openAccessibilitySettings sets sentToOsGrantFlow so the next '
        'missing probe resolves to restart', () async {
      final paster = _FakePaster(
        initial: const PasteCapability(
          status: PasteCapabilityStatus.permissionMissing,
          canPrompt: true,
        ),
      );
      final container = _container(paster: paster);
      addTearDown(container.dispose);

      final notifier = container.read(pasteCapabilityNotifierProvider.notifier);
      await notifier.openAccessibilitySettings();

      final state = container.read(pasteCapabilityNotifierProvider);
      expect(state.sentToOsGrantFlow, isTrue);
    });

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
  // requiredAction / needsRestart — the single recovery-action resolver every
  // UI surface shares. Pure function of three state fields:
  //   - capability?.status
  //   - pollingPhase == awaitingGrant (a live poll owns the screen)
  //   - sentToOsGrantFlow (has WhisPaste handed the user to the OS grant flow?)
  //
  // Missing + not-polling collapses to grant (never sent) or restart (sent).
  // Crucially, unlike the former timeout-only heuristic, `idle` after a
  // handoff still resolves to restart — stopping polling no longer silently
  // downgrades a granted-but-stale permission back to "Erlauben".
  // ---------------------------------------------------------------------------
  group('PasteCapabilityNotifier — requiredAction / needsRestart', () {
    /// Probe the notifier once with [status] (un-prompted) so `state.capability`
    /// is populated the same way the real flow does.
    Future<PasteCapabilityNotifier> probed(
      ProviderContainer container,
      _FakePaster paster,
      PasteCapabilityStatus status,
    ) async {
      final notifier = container.read(pasteCapabilityNotifierProvider.notifier);
      paster.nextResult = PasteCapability(status: status);
      await notifier.check();
      return notifier;
    }

    test('ready → none', () async {
      final paster = _FakePaster();
      final container = _container(paster: paster);
      addTearDown(container.dispose);

      final notifier = await probed(
        container,
        paster,
        PasteCapabilityStatus.ready,
      );
      expect(notifier.requiredAction, PastePermissionAction.none);
      expect(notifier.needsRestart, isFalse);
    });

    test('unsupported → none', () async {
      final paster = _FakePaster();
      final container = _container(paster: paster);
      addTearDown(container.dispose);

      final notifier = await probed(
        container,
        paster,
        PasteCapabilityStatus.unsupported,
      );
      expect(notifier.requiredAction, PastePermissionAction.none);
    });

    test('initial (unprobed) state → none', () async {
      final paster = _FakePaster();
      final container = _container(paster: paster);
      addTearDown(container.dispose);

      final notifier = container.read(pasteCapabilityNotifierProvider.notifier);
      expect(notifier.requiredAction, PastePermissionAction.none);
      expect(notifier.needsRestart, isFalse);
    });

    test('missing + not sent + idle → grant', () async {
      final paster = _FakePaster();
      final container = _container(paster: paster);
      addTearDown(container.dispose);

      final notifier = await probed(
        container,
        paster,
        PasteCapabilityStatus.permissionMissing,
      );
      expect(notifier.requiredAction, PastePermissionAction.grant);
      expect(notifier.needsRestart, isFalse);
    });

    test(
      'missing + sent + idle → restart (no poll timeout required)',
      () async {
        final paster = _FakePaster();
        final container = _container(paster: paster);
        addTearDown(container.dispose);

        final notifier = await probed(
          container,
          paster,
          PasteCapabilityStatus.permissionMissing,
        );
        // Hand the user to the OS grant flow (sets sentToOsGrantFlow); no poll.
        await notifier.openAccessibilitySettings();

        expect(notifier.requiredAction, PastePermissionAction.restart);
        expect(notifier.needsRestart, isTrue);
      },
    );

    test('missing + sent + awaitingGrant → none (waiting hint owns the '
        'screen)', () async {
      final paster = _FakePaster(
        initial: const PasteCapability(
          status: PasteCapabilityStatus.permissionMissing,
          canPrompt: true,
        ),
      );
      final container = _container(paster: paster);
      addTearDown(container.dispose);

      final notifier = container.read(pasteCapabilityNotifierProvider.notifier);
      await notifier.check(); // populate capability = missing
      await notifier.openAccessibilitySettings();
      notifier.startPolling(
        interval: const Duration(seconds: 10),
        timeout: const Duration(seconds: 10),
      );

      expect(notifier.requiredAction, PastePermissionAction.none);
      expect(notifier.needsRestart, isFalse);
      notifier.stopPolling();
    });

    test('missing + sent + timedOut → restart', () async {
      final paster = _FakePaster(
        initial: const PasteCapability(
          status: PasteCapabilityStatus.permissionMissing,
          canPrompt: true,
        ),
      );
      final container = _container(paster: paster);
      addTearDown(container.dispose);

      final notifier = container.read(pasteCapabilityNotifierProvider.notifier);
      await notifier.check(); // populate capability = missing
      await notifier.openAccessibilitySettings();
      notifier.startPolling(
        interval: const Duration(seconds: 5),
        timeout: const Duration(milliseconds: 20),
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(notifier.needsRestart, isTrue);
    });
  });

  group('PasteCapabilityNotifier — requestGrant spurious-restart race', () {
    // Regression for the "app auto-restarts / double-instances the instant the
    // user grants" bug. The app-level restart watch (app.dart's
    // _setupAutoPasteRestartWatch) reads `needsRestart` on EVERY notification
    // from this notifier and, when it sees `true`, fires the forced-restart
    // modal — which releases the single-instance lock and relaunches. So
    // requestGrant must never let an observer see a transient
    // `needsRestart == true`: between marking the OS-grant handoff
    // (sentToOsGrantFlow) and arming the poll (awaitingGrant) there was a window
    // where requiredAction resolved to `restart`, so every grant kicked off an
    // unwanted relaunch before polling could ever detect the real grant.
    test(
      'never surfaces needsRestart==true to a listener during the handoff',
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

        // Seed capability = missing exactly like the cold-start probe does.
        await notifier.check();

        // Gate the prompt round-trip so the pre-poll state is guaranteed to be
        // observed by the listener while requestGrant is suspended mid-flight —
        // the exact yield the real CGRequestPostEventAccess round-trip introduces.
        final gate = Completer<void>();
        paster.gate = gate;

        final observed = <bool>[];
        final sub = container.listen(pasteCapabilityNotifierProvider, (_, _) {
          observed.add(notifier.needsRestart);
        });

        final future = notifier.requestGrant(
          pollInterval: const Duration(milliseconds: 10),
          pollTimeout: const Duration(seconds: 30),
        );
        // Flush microtasks so any notification scheduled from the pre-await state
        // mutations is delivered while the prompt check is still gated.
        await pumpEventQueue();
        gate.complete();
        await future;
        // Stop observing before teardown cancels the live poll: stopping the poll
        // while still missing+sent legitimately resolves to `restart` (the
        // timeout/foreground path, covered separately) — that is the intended
        // post-handoff behavior, not the race this test guards.
        sub.close();

        expect(
          observed,
          everyElement(isFalse),
          reason:
              'A transient needsRestart==true during requestGrant makes the '
              'app-level restart watch fire a forced relaunch before polling can '
              'detect the granted permission — the endless-restart / '
              'double-instance bug.',
        );
      },
    );
  });

  group(
    'PasteCapabilityNotifier — requestGrant Settings deep-link vs native alert',
    () {
      // Regression for the live-reported window-stacking bug: macOS shows its
      // own PostEvent/Accessibility alert at most once per process. Firing our
      // Settings deep-link unconditionally right alongside that first alert
      // raced the two windows — System Settings landed on top of the
      // still-visible native alert, hiding the one control that actually
      // creates the grant entry. The deep-link is still required from the
      // SECOND call onward, where macOS is known to stay silent.
      late UrlLauncherPlatform original;
      late _FakeUrlLauncher fakeLauncher;

      setUp(() {
        original = UrlLauncherPlatform.instance;
        fakeLauncher = _FakeUrlLauncher();
        UrlLauncherPlatform.instance = fakeLauncher;
      });

      tearDown(() {
        UrlLauncherPlatform.instance = original;
      });

      test('first requestGrant call this process does not open Settings '
          '(the native alert is expected instead)', () async {
        final paster = _FakePaster();
        final container = _container(paster: paster);
        addTearDown(container.dispose);
        final notifier = container.read(
          pasteCapabilityNotifierProvider.notifier,
        );

        await notifier.requestGrant(
          pollInterval: const Duration(milliseconds: 10),
          pollTimeout: const Duration(milliseconds: 10),
        );

        expect(
          fakeLauncher.launchedUrls,
          isEmpty,
          reason:
              'the first call this process must leave Settings-opening to '
              "the OS's own alert, not race it with our own window",
        );
      });

      test('second requestGrant call this process DOES open Settings '
          '(macOS stays silent on repeat prompts)', () async {
        final paster = _FakePaster();
        final container = _container(paster: paster);
        addTearDown(container.dispose);
        final notifier = container.read(
          pasteCapabilityNotifierProvider.notifier,
        );

        await notifier.requestGrant(
          pollInterval: const Duration(milliseconds: 10),
          pollTimeout: const Duration(milliseconds: 10),
        );
        await notifier.requestGrant(
          pollInterval: const Duration(milliseconds: 10),
          pollTimeout: const Duration(milliseconds: 10),
        );

        expect(
          fakeLauncher.launchedUrls,
          hasLength(1),
          reason:
              'macOS shows no alert on the second prompt this process, so '
              'the deep-link is the only remaining path to Settings',
        );
      });
    },
  );

  group('PasteCapabilityNotifier — recheckOnForeground', () {
    test('no-op when already ready (skips the probe)', () async {
      final paster = _FakePaster(
        initial: const PasteCapability(status: PasteCapabilityStatus.ready),
      );
      final container = _container(paster: paster);
      addTearDown(container.dispose);

      final notifier = container.read(pasteCapabilityNotifierProvider.notifier);
      await notifier.check(); // populate `ready`
      paster.calls.clear();

      await notifier.recheckOnForeground();

      expect(
        paster.calls,
        isEmpty,
        reason: 'A ready capability needs no foreground re-probe',
      );
    });

    test('AX live-flip: a fresh probe that reads ready promotes state and '
        'clears the restart affordance', () async {
      final paster = _FakePaster(
        initial: const PasteCapability(
          status: PasteCapabilityStatus.permissionMissing,
          canPrompt: true,
        ),
      );
      final container = _container(paster: paster);
      addTearDown(container.dispose);

      final notifier = container.read(pasteCapabilityNotifierProvider.notifier);
      await notifier.openAccessibilitySettings();
      notifier.startPolling(
        interval: const Duration(seconds: 10),
        timeout: const Duration(seconds: 10),
      );

      // User returns from System Settings having actually granted it.
      paster.nextResult = const PasteCapability(
        status: PasteCapabilityStatus.ready,
      );
      await notifier.recheckOnForeground();

      expect(
        container.read(pasteCapabilityNotifierProvider).capability?.status,
        PasteCapabilityStatus.ready,
      );
      expect(notifier.needsRestart, isFalse);
    });

    test('MAS stale: foreground return with a still-missing probe stops the '
        'doomed poll so restart surfaces immediately', () async {
      final paster = _FakePaster(
        initial: const PasteCapability(
          status: PasteCapabilityStatus.permissionMissing,
          canPrompt: true,
        ),
      );
      final container = _container(paster: paster);
      addTearDown(container.dispose);

      final notifier = container.read(pasteCapabilityNotifierProvider.notifier);
      await notifier.openAccessibilitySettings();
      notifier.startPolling(
        interval: const Duration(seconds: 30),
        timeout: const Duration(seconds: 30),
      );
      expect(notifier.isPolling, isTrue);
      // While polling, requiredAction is none (waiting hint).
      expect(notifier.requiredAction, PastePermissionAction.none);

      // User returns from Settings; on MAS the probe is still cached-missing.
      await notifier.recheckOnForeground();

      expect(
        notifier.isPolling,
        isFalse,
        reason: 'The pointless poll must be stopped on foreground return',
      );
      expect(notifier.needsRestart, isTrue);
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

  group('PasteCapabilityNotifier — restart marker / restartWasIneffective', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('hydrateRestartMarker loads the persisted flag into state', () async {
      SharedPreferences.setMockInitialValues({
        kAutoPasteRestartMarkerKey: true,
      });
      final container = _container(paster: _FakePaster());
      addTearDown(container.dispose);
      final notifier = container.read(pasteCapabilityNotifierProvider.notifier);

      await notifier.hydrateRestartMarker();

      expect(
        container.read(pasteCapabilityNotifierProvider).restartAttempted,
        isTrue,
      );
    });

    test(
      'cold-start missing probe after a restart resolves to '
      'restartWasIneffective (grant action, honest copy) — not a naive restart',
      () async {
        SharedPreferences.setMockInitialValues({
          kAutoPasteRestartMarkerKey: true,
        });
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

        await notifier.hydrateRestartMarker();
        await notifier.check();

        // Fresh process: sentToOsGrantFlow is false, so the plain resolver
        // yields grant — but the persisted marker upgrades the *copy* to the
        // honest "restart didn't take" surface.
        expect(notifier.requiredAction, PastePermissionAction.grant);
        expect(notifier.restartWasIneffective, isTrue);
      },
    );

    test('a ready probe clears the persisted restart marker', () async {
      SharedPreferences.setMockInitialValues({
        kAutoPasteRestartMarkerKey: true,
      });
      final paster = _FakePaster(
        initial: const PasteCapability(status: PasteCapabilityStatus.ready),
      );
      final container = _container(paster: paster);
      addTearDown(container.dispose);
      final notifier = container.read(pasteCapabilityNotifierProvider.notifier);

      await notifier.hydrateRestartMarker();
      await notifier.check();

      expect(
        container.read(pasteCapabilityNotifierProvider).restartAttempted,
        isFalse,
      );
      expect(notifier.restartWasIneffective, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kAutoPasteRestartMarkerKey), isNull);
    });

    test('markRestartAttempted sets state and persists the marker', () async {
      final container = _container(paster: _FakePaster());
      addTearDown(container.dispose);
      final notifier = container.read(pasteCapabilityNotifierProvider.notifier);

      await notifier.markRestartAttempted();

      expect(
        container.read(pasteCapabilityNotifierProvider).restartAttempted,
        isTrue,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kAutoPasteRestartMarkerKey), isTrue);
    });

    test(
      'restartForGrant marks the persisted marker BEFORE relaunching so '
      'every manual restart surface (not just the modal) is loop-aware',
      () async {
        const channel = MethodChannel('com.whispaste.app_lifecycle');
        final calls = <String>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              calls.add(call.method);
              return null;
            });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null);
        });

        final container = _container(paster: _FakePaster());
        addTearDown(container.dispose);
        final notifier = container.read(
          pasteCapabilityNotifierProvider.notifier,
        );

        await notifier.restartForGrant();

        expect(
          container.read(pasteCapabilityNotifierProvider).restartAttempted,
          isTrue,
          reason:
              'restartForGrant must set the marker so the fresh process can '
              'detect an ineffective restart no matter which button was pressed.',
        );
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool(kAutoPasteRestartMarkerKey), isTrue);
        expect(calls, contains('restart'));
      },
    );

    test('restartWasIneffective is false without a marker even when '
        'permission is missing (ordinary first-contact state)', () async {
      final paster = _FakePaster(
        initial: const PasteCapability(
          status: PasteCapabilityStatus.permissionMissing,
          canPrompt: true,
        ),
      );
      final container = _container(paster: paster);
      addTearDown(container.dispose);
      final notifier = container.read(pasteCapabilityNotifierProvider.notifier);

      await notifier.check();

      expect(notifier.requiredAction, PastePermissionAction.grant);
      expect(notifier.restartWasIneffective, isFalse);
    });
  });
}
