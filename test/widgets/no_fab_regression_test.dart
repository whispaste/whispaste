/// Regression test: the in-app recording FAB must not exist in the widget tree.
///
/// Guards against re-introduction of WpRecordingFab (or any FloatingActionButton)
/// in the _AppShell Scaffold after the FAB-removal in settings-optimierung/01.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/app.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/services/autostart_service.dart';
import 'package:whispaste/services/floating_button/floating_button_service.dart';
import 'package:whispaste/services/floating_button/floating_button_controller.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_service.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_controller.dart';
import 'package:whispaste/services/hardware_info_service.dart';
import 'package:whispaste/services/hotkey_service.dart';
import 'package:whispaste/services/recording_orchestrator.dart';
import 'package:whispaste/services/tray_service.dart';
import 'package:whispaste/services/update_service.dart';
import 'package:whispaste/services/stt/stt_bundle.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ---------------------------------------------------------------------------
// No-op fakes — avoid platform-channel and subprocess side effects
// ---------------------------------------------------------------------------

class _FakeHotkeyService extends HotkeyService {
  @override
  void build() {}
}

class _FakeTrayService extends TrayService {
  @override
  void build() {}
}

class _FakeAutostartService extends AutostartService {
  @override
  bool build() => false;
}

class _FakeFloatingButtonService extends FloatingButtonService {
  @override
  FloatingButtonController? createController() => null;
}

class _FakeFloatingOverlayService extends FloatingOverlayService {
  @override
  FloatingOverlayController? createController() => null;
}

class _FakeOrchestrator extends RecordingOrchestrator {
  @override
  void build() {}
}

class _FakeUpdateNotifier extends UpdateNotifier {
  @override
  UpdateState build() => const UpdateState();
}

class _FakeSttNotifier extends SttServerStateNotifier {
  @override
  SttStatus build() => const SttStatus(serverState: SttServerState.ready);
}

class _FakeSettingsNotifier extends SettingsNotifier {
  @override
  Future<AppSettings> build() async =>
      AppSettings.defaults.copyWith(onboardingCompleted: true);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('_AppShell Scaffold has no FloatingActionButton in widget tree', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          historyDatabaseProvider.overrideWith((ref) {
            final db = HistoryDatabase.forTesting(NativeDatabase.memory());
            ref.onDispose(db.close);
            return db;
          }),
          settingsProvider.overrideWith(_FakeSettingsNotifier.new),
          hotkeyServiceProvider.overrideWith(_FakeHotkeyService.new),
          trayServiceProvider.overrideWith(_FakeTrayService.new),
          autostartServiceProvider.overrideWith(_FakeAutostartService.new),
          floatingButtonServiceProvider.overrideWith(
            _FakeFloatingButtonService.new,
          ),
          floatingOverlayServiceProvider.overrideWith(
            _FakeFloatingOverlayService.new,
          ),
          recordingOrchestratorProvider.overrideWith(_FakeOrchestrator.new),
          updateProvider.overrideWith(_FakeUpdateNotifier.new),
          localSttBundleProvider.overrideWith(_FakeSttNotifier.new),
          gpuInfoProvider.overrideWith(
            (ref) async => const GpuInfo(vendor: GpuVendor.none, name: 'Test'),
          ),
        ],
        child: const WhisPasteApp(),
      ),
    );

    // Settle after first frame (async settings load, window manager, etc.)
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // The Scaffold produced by _AppShell must have no floatingActionButton.
    // FloatingActionButtonLocation widget is only mounted when a FAB exists.
    expect(
      find.byType(FloatingActionButton),
      findsNothing,
      reason:
          'WpRecordingFab was removed — no FAB must appear in the app shell',
    );

    // Drain Drift/Riverpod cleanup timers so the test framework's
    // !timersPending invariant does not fire from the in-memory DB's
    // StreamQueryStore.markAsClosed scheduling a zero-duration timer.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
