// UIA-SHL-01: "Start recording" in the floating button's menu toggles the
// recording without pulling the main window to the front.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/services/smart_mode/smart_mode_presets.dart';
import 'package:whispaste/services/floating_button/floating_button_controller.dart';
import 'package:whispaste/services/floating_button/floating_button_events.dart';
import 'package:whispaste/services/floating_button/floating_button_service.dart';
import 'package:whispaste/services/recording_orchestrator.dart';
import 'package:whispaste/core/theme/overlay_customization.dart';

class _EventController implements FloatingButtonController {
  final _events = StreamController<FloatingButtonEvent>.broadcast();

  @override
  Stream<FloatingButtonEvent> get events => _events.stream;

  @override
  Future<void> setContextMenuItems(List<Map<String, String>> items) async {}

  @override
  Future<void> dispose() => _events.close();

  @override
  Future<void> show({double x = 200, double y = 200, int size = 56}) async {}

  @override
  Future<void> hide() async {}

  @override
  Future<void> setState(FloatingButtonVisualState state) async {}

  @override
  Future<void> setPosition(double x, double y) async {}

  @override
  Future<void> setSize(int size) async {}

  @override
  Future<void> setTheme({
    required String background,
    required String wave,
    FloatingButtonLook look = FloatingButtonLook.defaults,
  }) async {}

  @override
  Future<({double x, double y})?> getPosition() async => null;
}

class _TestableService extends FloatingButtonService {
  _TestableService(this._fake);
  final _EventController _fake;

  @override
  FloatingButtonController? createController() => _fake;
}

class _RecordingOrchestrator extends RecordingOrchestrator {
  int toggles = 0;

  @override
  void build() {}

  @override
  Future<void> toggleRecording({
    RecordingTarget target = RecordingTarget.clipboard,
    SmartModePreset? forcedSmartModePreset,
    String? languageOverride,
    double? silenceTimeoutOverride,
  }) async => toggles++;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    '"Start recording" toggles recording without fronting the window',
    () async {
      const windowChannel = MethodChannel('window_manager');
      const lifecycleChannel = MethodChannel('com.whispaste.app_lifecycle');
      final windowCalls = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(windowChannel, (call) async {
        windowCalls.add(call.method);
        return null;
      });
      messenger.setMockMethodCallHandler(lifecycleChannel, (call) async {
        windowCalls.add('lifecycle.${call.method}');
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(windowChannel, null);
        messenger.setMockMethodCallHandler(lifecycleChannel, null);
      });

      final fake = _EventController();
      final orchestrator = _RecordingOrchestrator();
      final container = ProviderContainer(
        overrides: [
          floatingButtonServiceProvider.overrideWith(
            () => _TestableService(fake),
          ),
          recordingOrchestratorProvider.overrideWith(() => orchestrator),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await fake.dispose();
      });
      container.listen(floatingButtonServiceProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);

      fake._events.add(
        const FloatingButtonContextMenuSelected('__new_recording__'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(orchestrator.toggles, 1);
      expect(windowCalls, isEmpty);
    },
  );
}
