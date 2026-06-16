import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_controller_interface.dart';
import 'package:whispaste/services/floating_overlay/overlay_render_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const name = 'test/overlay_render';
  const codec = StandardMethodCodec();
  final binaryMessenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  Future<void> sendFromNative(String method, Object? args) {
    return binaryMessenger.handlePlatformMessage(
      name,
      codec.encodeMethodCall(MethodCall(method, args)),
      (_) {},
    );
  }

  group('OverlayRenderChannel — inbound (native → render engine)', () {
    test('updateSnapshot rebuilds the snapshot via fromMap', () async {
      FloatingOverlaySnapshot? received;
      final channel = OverlayRenderChannel(
        name: name,
        onSnapshot: (s) => received = s,
        onWaveformBars: (_) {},
      );
      addTearDown(channel.dispose);

      const snap = FloatingOverlaySnapshot(
        visible: true,
        state: OverlayVisualState.transcribing,
        isDark: false,
        compact: true,
        label: 'Transcribing',
        elapsed: '0:03',
      );
      await sendFromNative('updateSnapshot', snap.toMap());

      expect(received, isNotNull);
      expect(received!.visible, isTrue);
      expect(received!.state, OverlayVisualState.transcribing);
      expect(received!.compact, isTrue);
      expect(received!.label, 'Transcribing');
      expect(received!.elapsed, '0:03');
    });

    test('setWaveformBars forwards a normalised double list', () async {
      List<double>? bars;
      final channel = OverlayRenderChannel(
        name: name,
        onSnapshot: (_) {},
        onWaveformBars: (b) => bars = b,
      );
      addTearDown(channel.dispose);

      await sendFromNative('setWaveformBars', {
        'bars': [0.1, 0.5, 1.0],
      });

      expect(bars, [0.1, 0.5, 1.0]);
    });
  });

  group('OverlayRenderChannel — outbound (render engine → native)', () {
    test('startDrag / bodyClicked / showContextMenu invoke the host', () async {
      final calls = <String>[];
      const probe = MethodChannel(name);
      binaryMessenger.setMockMethodCallHandler(probe, (call) async {
        calls.add(call.method);
        return null;
      });
      addTearDown(() => binaryMessenger.setMockMethodCallHandler(probe, null));

      final channel = OverlayRenderChannel(
        name: name,
        onSnapshot: (_) {},
        onWaveformBars: (_) {},
      );
      addTearDown(channel.dispose);

      channel.startDrag();
      channel.bodyClicked();
      channel.showContextMenu();
      await Future<void>.delayed(Duration.zero);

      expect(calls, ['startDrag', 'bodyClicked', 'showContextMenu']);
    });
  });

  group('OverlayRenderChannel — receive telemetry (throttled debugPrint)', () {
    const snap = FloatingOverlaySnapshot(
      visible: true,
      state: OverlayVisualState.recording,
      isDark: true,
      compact: false,
      label: '',
    );

    // Helper: intercept debugPrint and restore after the test.
    List<String> captureDebugPrint() {
      final logs = <String>[];
      final saved = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };
      addTearDown(() => debugPrint = saved);
      return logs;
    }

    test('onSnapshot logs on first arrival', () async {
      final logs = captureDebugPrint();
      final channel = OverlayRenderChannel(
        name: name,
        onSnapshot: (_) {},
        onWaveformBars: (_) {},
        clock: () => DateTime(2026, 1, 1),
      );
      addTearDown(channel.dispose);

      await sendFromNative('updateSnapshot', snap.toMap());

      expect(
        logs.where((l) => l.contains('[overlay-engine] onSnapshot')),
        isNotEmpty,
        reason: 'First arrival must always produce a log',
      );
    });

    test('onSnapshot throttled: at most one log per throttle window', () async {
      final logs = captureDebugPrint();
      var now = DateTime(2026, 1, 1);
      final channel = OverlayRenderChannel(
        name: name,
        onSnapshot: (_) {},
        onWaveformBars: (_) {},
        clock: () => now,
      );
      addTearDown(channel.dispose);

      // Three arrivals within the same throttle window.
      await sendFromNative('updateSnapshot', snap.toMap());
      await sendFromNative('updateSnapshot', snap.toMap());
      await sendFromNative('updateSnapshot', snap.toMap());

      expect(
        logs.where((l) => l.contains('[overlay-engine] onSnapshot')).length,
        1,
        reason: 'Only the first arrival logs within the throttle window',
      );

      // Advance clock past the window — next arrival must log again.
      logs.clear();
      now = now.add(const Duration(seconds: 1));
      await sendFromNative('updateSnapshot', snap.toMap());

      expect(
        logs.where((l) => l.contains('[overlay-engine] onSnapshot')).length,
        1,
        reason: 'After throttle window expires a new log is emitted',
      );
    });

    test(
      'onWaveformBars throttled: at most one log per throttle window at ~30Hz',
      () async {
        final logs = captureDebugPrint();
        final now = DateTime(2026, 1, 1);
        final channel = OverlayRenderChannel(
          name: name,
          onSnapshot: (_) {},
          onWaveformBars: (_) {},
          clock: () => now,
        );
        addTearDown(channel.dispose);

        // Simulate three ~30Hz frames arriving in the same throttle window.
        final bars = [0.1, 0.5, 1.0];
        await sendFromNative('setWaveformBars', {'bars': bars});
        await sendFromNative('setWaveformBars', {'bars': bars});
        await sendFromNative('setWaveformBars', {'bars': bars});

        expect(
          logs
              .where((l) => l.contains('[overlay-engine] onWaveformBars'))
              .length,
          1,
          reason: 'Only the first waveform frame per window logs',
        );
      },
    );

    test('notifyReady always logs without throttle', () async {
      final logs = captureDebugPrint();

      // Mock outbound so invokeMethod("ready") does not fail.
      const probe = MethodChannel(name);
      binaryMessenger.setMockMethodCallHandler(probe, (_) async => null);
      addTearDown(() => binaryMessenger.setMockMethodCallHandler(probe, null));

      final channel = OverlayRenderChannel(
        name: name,
        onSnapshot: (_) {},
        onWaveformBars: (_) {},
      );
      addTearDown(channel.dispose);

      channel.notifyReady();

      expect(
        logs.where((l) => l.contains('[overlay-engine] notifyReady')),
        isNotEmpty,
        reason: 'notifyReady must log on every call — no throttle',
      );
    });
  });
}
