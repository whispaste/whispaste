/// Widget tests for [WpServiceBootstrap] — verifies that the
/// [RecordingTriggerHandler] survives parent rebuilds so Push-to-Talk
/// keyDown/keyUp pairs are wired to the SAME handler instance.
///
/// This is the regression net for the bug described in
/// `.scratch/hotkey-modifier-storage-fix/issues/06-trigger-handler-persistent-state.md`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/services/autostart_service.dart';
import 'package:whispaste/services/clipboard_history/clipboard_history_monitor_service.dart';
import 'package:whispaste/services/floating_button/floating_button_controller.dart';
import 'package:whispaste/services/floating_button/floating_button_service.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_controller.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_service.dart';
import 'package:whispaste/core/navigation/page_state.dart';
import 'package:whispaste/services/hotkey_service.dart';
import 'package:whispaste/services/paste/paste_capability_notifier.dart';
import 'package:whispaste/services/recording_orchestrator.dart';
import 'package:whispaste/services/side_panel/side_panel_controller_interface.dart';
import 'package:whispaste/services/side_panel/side_panel_service.dart';
import 'package:whispaste/services/tray_service.dart';
import 'package:whispaste/widgets/service_bootstrap.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

/// Fake [HotkeyService] that exposes the assigned callbacks for direct
/// invocation in tests. Skips real platform registration entirely.
class _FakeHotkeyService extends HotkeyService {
  _FakeHotkeyService({this.fakeSupportsKeyUp = true});

  final bool fakeSupportsKeyUp;

  @override
  bool get supportsKeyUp => fakeSupportsKeyUp;

  @override
  void build() {
    // Skip platform registration — production-side wiring is irrelevant
    // for this test; we only care about the [onHotkeyPressed] /
    // [onHotkeyReleased] field assignments coming from the bootstrap.
  }
}

/// Counter-mock orchestrator — records how many times each entry point
/// was invoked from the [RecordingTriggerHandler].
class _CounterOrchestrator extends RecordingOrchestrator {
  int startCalls = 0;
  int stopCalls = 0;
  int toggleCalls = 0;

  @override
  void build() {
    // Do not run the real orchestrator's heavy setup.
  }

  @override
  Future<void> startRecording({
    RecordingTarget target = RecordingTarget.clipboard,
  }) async {
    startCalls++;
  }

  @override
  Future<void> stopRecording() async {
    stopCalls++;
  }

  @override
  Future<void> toggleRecording({
    RecordingTarget target = RecordingTarget.clipboard,
  }) async {
    toggleCalls++;
  }
}

/// No-op tray service — avoids platform-channel calls in tests.
class _FakeTrayService extends TrayService {
  @override
  void build() {}
}

/// Capability notifier that only counts the recovery call — the recovery
/// itself talks to TCC and System Settings, neither of which exists here.
/// What these tests check is which of the two tray branches was taken.
class _RecoveryCountingCapabilityNotifier extends PasteCapabilityNotifier {
  int recoveryCalls = 0;

  @override
  PasteCapabilityState build() => const PasteCapabilityState();

  @override
  Future<void> runMissingPermissionRecovery() async {
    recoveryCalls++;
  }
}

/// No-op autostart service — avoids platform-channel calls in tests.
class _FakeAutostartService extends AutostartService {
  @override
  bool build() => false;
}

/// No-op floating button service.
class _FakeFloatingButtonService extends FloatingButtonService {
  @override
  FloatingButtonController? createController() => null;
}

/// No-op floating overlay service.
class _FakeFloatingOverlayService extends FloatingOverlayService {
  @override
  FloatingOverlayController? createController() => null;
}

/// No-op side panel service.
class _FakeSidePanelService extends SidePanelService {
  @override
  SidePanelController? createController() => null;
}

/// No-op clipboard-history monitor service: skips registering the real
/// MethodChannel handler entirely.
class _FakeClipboardHistoryMonitorService
    extends ClipboardHistoryMonitorService {
  @override
  void build() {}
}

/// Fake settings notifier that returns a fixed [AppSettings] synchronously
/// and exposes a [setPushToTalk] setter to flip the value at runtime.
///
/// `build()` is intentionally NOT marked async so the state transitions
/// from [AsyncLoading] to [AsyncData] within the same microtask, before
/// any caller in the bootstrap reads it.
class _FakeSettingsNotifier extends SettingsNotifier {
  _FakeSettingsNotifier({required this._pushToTalk});

  bool _pushToTalk;

  @override
  Future<AppSettings> build() {
    return Future.value(
      AppSettings(audioInput: AudioInputSettings(pushToTalk: _pushToTalk)),
    );
  }

  void setPushToTalk(bool value) {
    _pushToTalk = value;
    state = AsyncData(
      AppSettings(audioInput: AudioInputSettings(pushToTalk: value)),
    );
  }
}

// ---------------------------------------------------------------------------
// Harness — parent widget that can force a rebuild between events
// ---------------------------------------------------------------------------

/// Parent widget exposing a [GlobalKey] so tests can trigger a
/// `setState` on the parent and force [WpServiceBootstrap] to rebuild,
/// reproducing the production rebuild that happens when
/// [recordingPhaseProvider] fires.
class _RebuildHarness extends StatefulWidget {
  const _RebuildHarness({super.key});

  @override
  State<_RebuildHarness> createState() => _RebuildHarnessState();
}

class _RebuildHarnessState extends State<_RebuildHarness> {
  int _rebuildTick = 0;

  void forceRebuild() => setState(() => _rebuildTick++);

  @override
  Widget build(BuildContext context) {
    return WpServiceBootstrap(
      key: const ValueKey('bootstrap'),
      // Use the tick in the subtree so Flutter does not optimize the rebuild
      // away — ensures the bootstrap widget's element rebuilds too.
      child: Text('tick=$_rebuildTick'),
    );
  }
}

/// Builds the full widget tree with all heavy providers overridden.
Widget _makeApp({
  required _FakeHotkeyService hotkeySvc,
  required _CounterOrchestrator orchestrator,
  required _FakeSettingsNotifier settings,
  GlobalKey<_RebuildHarnessState>? harnessKey,
  PasteCapabilityNotifier Function()? capabilityNotifier,
}) {
  return ProviderScope(
    overrides: [
      if (capabilityNotifier != null)
        pasteCapabilityNotifierProvider.overrideWith(capabilityNotifier),
      hotkeyServiceProvider.overrideWith(() => hotkeySvc),
      recordingOrchestratorProvider.overrideWith(() => orchestrator),
      trayServiceProvider.overrideWith(_FakeTrayService.new),
      autostartServiceProvider.overrideWith(_FakeAutostartService.new),
      floatingButtonServiceProvider.overrideWith(
        _FakeFloatingButtonService.new,
      ),
      floatingOverlayServiceProvider.overrideWith(
        _FakeFloatingOverlayService.new,
      ),
      sidePanelServiceProvider.overrideWith(_FakeSidePanelService.new),
      clipboardHistoryMonitorServiceProvider.overrideWith(
        _FakeClipboardHistoryMonitorService.new,
      ),
      settingsProvider.overrideWith(() => settings),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      home: _RebuildHarness(key: harnessKey),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WpServiceBootstrap — trigger handler survives rebuilds', () {
    testWidgets(
      'Test 1: PTT keyDown → rebuild → keyUp still calls stopRecording',
      (tester) async {
        final hotkeySvc = _FakeHotkeyService(fakeSupportsKeyUp: true);
        final orchestrator = _CounterOrchestrator();
        final settings = _FakeSettingsNotifier(pushToTalk: true);
        final harnessKey = GlobalKey<_RebuildHarnessState>();

        await tester.pumpWidget(
          _makeApp(
            hotkeySvc: hotkeySvc,
            orchestrator: orchestrator,
            settings: settings,
            harnessKey: harnessKey,
          ),
        );
        // Let the post-frame callback + async settings build settle so the
        // closure-read of pushToTalk sees the overridden value.
        await tester.pumpAndSettle();

        // Force-initialise the settings provider so its async build resolves
        // before the trigger handler reads it. (In production, the settings
        // provider is read by many widgets long before the first hotkey.)
        final container = ProviderScope.containerOf(
          tester.element(find.byType(MaterialApp)),
        );
        await container.read(settingsProvider.future);

        // Sanity: the bootstrap wired up both callbacks.
        expect(hotkeySvc.onHotkeyPressed, isNotNull);
        expect(hotkeySvc.onHotkeyReleased, isNotNull);

        // 1. keyDown → startRecording is invoked.
        hotkeySvc.onHotkeyPressed!.call();
        await tester.pump();
        expect(orchestrator.startCalls, equals(1));

        // 2. Force a parent rebuild — this mimics the production rebuild that
        //    happens when recordingPhaseProvider fires after startRecording.
        harnessKey.currentState!.forceRebuild();
        await tester.pump();

        // 3. Wait > 100 ms of real wall-clock time so the anti-glitch
        //    threshold (which uses [DateTime.now], not fake-async clock)
        //    permits stopRecording. Must use [tester.runAsync] so the delay
        //    escapes flutter_test's fake-async zone.
        await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 120)),
        );
        await tester.pump();

        // 4. keyUp must call stopRecording on the SAME handler that observed
        //    the keyDown — if the handler was re-instantiated on rebuild, its
        //    [_keyDownAt] is null and stopRecording is silently skipped.
        hotkeySvc.onHotkeyReleased!.call();
        await tester.pump();
        expect(
          orchestrator.stopCalls,
          equals(1),
          reason:
              'Handler must keep its _keyDownAt state across bootstrap rebuilds',
        );
      },
    );

    testWidgets('Test 2: hotkey callback identity is stable across rebuilds', (
      tester,
    ) async {
      final hotkeySvc = _FakeHotkeyService(fakeSupportsKeyUp: true);
      final orchestrator = _CounterOrchestrator();
      final settings = _FakeSettingsNotifier(pushToTalk: true);
      final harnessKey = GlobalKey<_RebuildHarnessState>();

      await tester.pumpWidget(
        _makeApp(
          hotkeySvc: hotkeySvc,
          orchestrator: orchestrator,
          settings: settings,
          harnessKey: harnessKey,
        ),
      );
      await tester.pumpAndSettle();

      // Capture the wired-up callback references.
      final onPressBefore = hotkeySvc.onHotkeyPressed;
      final onReleaseBefore = hotkeySvc.onHotkeyReleased;
      expect(onPressBefore, isNotNull);
      expect(onReleaseBefore, isNotNull);

      // Force a parent rebuild — the production bug recreated the handler
      // (and therefore the bound methods) on every rebuild.
      harnessKey.currentState!.forceRebuild();
      await tester.pump();

      // Same bound-method references → same underlying handler instance.
      expect(
        identical(hotkeySvc.onHotkeyPressed, onPressBefore),
        isTrue,
        reason:
            'onHotkeyPressed must point at the same handler method across rebuilds',
      );
      expect(
        identical(hotkeySvc.onHotkeyReleased, onReleaseBefore),
        isTrue,
        reason:
            'onHotkeyReleased must point at the same handler method across rebuilds',
      );
    });

    testWidgets(
      'Test 3: toggle-mode rebuild-safe — two keyDowns yield two toggleRecording calls',
      (tester) async {
        final hotkeySvc = _FakeHotkeyService(fakeSupportsKeyUp: true);
        final orchestrator = _CounterOrchestrator();
        final settings = _FakeSettingsNotifier(pushToTalk: false);
        final harnessKey = GlobalKey<_RebuildHarnessState>();

        await tester.pumpWidget(
          _makeApp(
            hotkeySvc: hotkeySvc,
            orchestrator: orchestrator,
            settings: settings,
            harnessKey: harnessKey,
          ),
        );
        await tester.pumpAndSettle();

        // Ensure settings are loaded so the closure reads pushToTalk=false.
        final container = ProviderScope.containerOf(
          tester.element(find.byType(MaterialApp)),
        );
        await container.read(settingsProvider.future);

        hotkeySvc.onHotkeyPressed!.call();
        await tester.pump();
        expect(orchestrator.toggleCalls, equals(1));

        // Rebuild the bootstrap mid-stream.
        harnessKey.currentState!.forceRebuild();
        await tester.pump();

        hotkeySvc.onHotkeyPressed!.call();
        await tester.pump();
        expect(orchestrator.toggleCalls, equals(2));
        expect(orchestrator.startCalls, equals(0));
        expect(orchestrator.stopCalls, equals(0));
      },
    );

    testWidgets(
      'Test 4: settings change at runtime — closure reader picks up new pushToTalk value',
      (tester) async {
        final hotkeySvc = _FakeHotkeyService(fakeSupportsKeyUp: true);
        final orchestrator = _CounterOrchestrator();
        final settings = _FakeSettingsNotifier(pushToTalk: false);
        final harnessKey = GlobalKey<_RebuildHarnessState>();

        await tester.pumpWidget(
          _makeApp(
            hotkeySvc: hotkeySvc,
            orchestrator: orchestrator,
            settings: settings,
            harnessKey: harnessKey,
          ),
        );
        await tester.pumpAndSettle();

        final container = ProviderScope.containerOf(
          tester.element(find.byType(MaterialApp)),
        );
        await container.read(settingsProvider.future);

        // PTT off → keyDown goes through the toggle branch.
        hotkeySvc.onHotkeyPressed!.call();
        await tester.pump();
        expect(orchestrator.toggleCalls, equals(1));
        expect(orchestrator.startCalls, equals(0));

        // Flip the setting at runtime and force a parent rebuild.
        settings.setPushToTalk(true);
        harnessKey.currentState!.forceRebuild();
        await tester.pump();

        // The same handler now sees pushToTalk=true via its closure reader,
        // so the next keyDown calls startRecording instead of toggleRecording.
        hotkeySvc.onHotkeyPressed!.call();
        await tester.pump();
        expect(
          orchestrator.startCalls,
          equals(1),
          reason: 'Closure reader must see the new pushToTalk value live',
        );
        expect(orchestrator.toggleCalls, equals(1));
      },
    );
  });

  // =========================================================================
  // Tray "action needed" routing. The tray entry outlives the other two
  // paste-failure surfaces (the notification expires, the Dock bounce stops),
  // so for a blocked Auto-Paste permission it is usually the only one left
  // when the user gets around to acting — and it must fix the thing rather
  // than drop the user on a settings page to find the fix themselves.
  // =========================================================================
  group('WpServiceBootstrap — tray "action needed" routing', () {
    Future<(ProviderContainer, _RecoveryCountingCapabilityNotifier)> pumpApp(
      WidgetTester tester,
    ) async {
      final capability = _RecoveryCountingCapabilityNotifier();
      await tester.pumpWidget(
        _makeApp(
          hotkeySvc: _FakeHotkeyService(),
          orchestrator: _CounterOrchestrator(),
          settings: _FakeSettingsNotifier(pushToTalk: false),
          capabilityNotifier: () => capability,
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MaterialApp)),
      );
      await container.read(settingsProvider.future);
      return (container, capability);
    }

    testWidgets('the permission entry runs the recovery in place', (
      tester,
    ) async {
      final (container, capability) = await pumpApp(tester);

      container.read(trayServiceProvider.notifier).onActionNeededTap!(
        kTrayPastePermissionActionNeededKey,
      );
      await tester.pumpAndSettle();

      expect(capability.recoveryCalls, equals(1));
      expect(
        container.read(activePageProvider),
        isNot('settings'),
        reason:
            'Navigating to settings is exactly the hunt-for-it-yourself dead '
            'end this branch exists to remove.',
      );
    });

    testWidgets('other entries still jump to the Auto-Paste settings', (
      tester,
    ) async {
      final (container, capability) = await pumpApp(tester);

      container.read(trayServiceProvider.notifier).onActionNeededTap!(
        kTrayPasteActionNeededKey,
      );
      await tester.pumpAndSettle();

      expect(container.read(activePageProvider), 'settings');
      expect(
        container.read(settingsScrollTargetProvider),
        'afterTranscription',
      );
      expect(
        capability.recoveryCalls,
        equals(0),
        reason:
            'A missing target app or an elevated window is not a permission '
            'problem — running the TCC recovery there would prompt for '
            'nothing.',
      );
    });
  });
}
