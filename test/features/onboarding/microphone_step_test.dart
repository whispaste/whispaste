/// Widget tests for [MicrophoneStep] (onboarding step 2).
///
/// These tests cover the phase machine — idle → requesting → denied / silent /
/// ready — and the device-picker behaviour that lets users escape a wrong
/// default mic without leaving onboarding. Speech detection itself is covered
/// in `mic_probe_test.dart`; here we use a fake probe that returns scripted
/// outcomes so the widget logic is the focus.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:whispaste/features/onboarding/mic_probe.dart';
import 'package:whispaste/features/onboarding/steps/microphone_step.dart';
import 'package:whispaste/services/audio_routing_service.dart';
import 'package:whispaste/widgets/wp_accent_button.dart';

import '../../fixtures/fake_mic_recorder.dart';
import '../../fixtures/test_helpers.dart';

/// Scripted [OnboardingMicProbe] — returns outcomes from a queue so a test
/// can verify the retry / device-switch path without driving the underlying
/// PCM pipeline.
class _FakeProbe extends OnboardingMicProbe {
  _FakeProbe({
    required List<MicProbeOutcome> outcomes,
    this.devices = const <InputDevice>[],
  }) : _outcomes = List.of(outcomes),
       super(recorder: FakeMicRecorder());

  final List<MicProbeOutcome> _outcomes;
  final List<InputDevice> devices;

  final List<InputDevice?> startCalls = <InputDevice?>[];
  int stopCalls = 0;
  int disposeCalls = 0;

  @override
  Future<MicProbeOutcome> start({InputDevice? device}) async {
    startCalls.add(device);
    if (_outcomes.isEmpty) return MicProbeOutcome.silence;
    return _outcomes.removeAt(0);
  }

  @override
  Future<List<InputDevice>> listInputDevices() async => devices;

  @override
  Future<void> stop() async {
    stopCalls++;
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }
}

/// Test seam for [AudioRoutingService]. By default `isSupported = false` so
/// the widget treats the host like Linux/Windows and forwards the picker's
/// selection straight into `RecordConfig.device`. Flip [isSupportedOverride]
/// to exercise the macOS routing path.
class _FakeRouting implements AudioRoutingService {
  _FakeRouting({
    this.isSupportedOverride = false,
    this.currentDefault,
    this.devices = const <InputDevice>[],
  });

  bool isSupportedOverride;
  String? currentDefault;
  List<InputDevice> devices;

  final List<String> setCalls = <String>[];

  @override
  bool get isSupported => isSupportedOverride;

  @override
  Future<String?> getDefaultInputDevice() async => currentDefault;

  @override
  Future<bool> setDefaultInputDevice(String uid) async {
    setCalls.add(uid);
    currentDefault = uid;
    return true;
  }

  @override
  Future<List<InputDevice>> listInputDevices() async => devices;
}

void _noop() {}

WpAccentButton _findNext(WidgetTester tester) => tester.widget<WpAccentButton>(
  find.ancestor(of: find.text('Next'), matching: find.byType(WpAccentButton)),
);

void _expectNextEnabled(WidgetTester tester) {
  expect(
    _findNext(tester).onPressed,
    isNotNull,
    reason: 'Next must be enabled',
  );
}

void _expectNextDisabled(WidgetTester tester) {
  expect(_findNext(tester).onPressed, isNull, reason: 'Next must be gated');
}

Future<_FakeProbe> _pumpStep(
  WidgetTester tester, {
  required List<MicProbeOutcome> outcomes,
  List<InputDevice> devices = const <InputDevice>[],
  AudioRoutingService? routing,
  Locale locale = const Locale('en'),
}) async {
  final probe = _FakeProbe(outcomes: outcomes, devices: devices);
  await tester.pumpWidget(
    makeTestable(
      MicrophoneStep(
        onNext: _noop,
        onBack: _noop,
        probeFactory: () => probe,
        routing: routing ?? _FakeRouting(),
      ),
      size: const Size(1280, 980),
      locale: locale,
    ),
  );
  await tester.pumpAndSettle();
  return probe;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MicrophoneStep', () {
    testWidgets('initial idle render shows Grant button, Next disabled', (
      tester,
    ) async {
      await _pumpStep(tester, outcomes: const []);

      expect(find.text('Grant Access'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);

      _expectNextDisabled(tester);
    });

    testWidgets('permissionDenied outcome surfaces TCC instructions', (
      tester,
    ) async {
      await _pumpStep(
        tester,
        outcomes: const [MicProbeOutcome.permissionDenied],
      );

      await tester.tap(find.text('Grant Access'));
      await tester.pumpAndSettle();

      expect(find.text('Microphone access denied'), findsOneWidget);
      expect(
        find.text('Open your system settings to grant microphone access'),
        findsOneWidget,
      );
      // Grant button is still rendered so the user can retry after fixing
      // the OS-level permission.
      expect(find.text('Grant Access'), findsOneWidget);
    });

    testWidgets('silence outcome surfaces retry CTA and warning copy', (
      tester,
    ) async {
      await _pumpStep(tester, outcomes: const [MicProbeOutcome.silence]);

      await tester.tap(find.text('Grant Access'));
      await tester.pumpAndSettle();

      expect(find.textContaining("We can't hear anything"), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);

      _expectNextDisabled(tester);
    });

    testWidgets('speechDetected outcome unlocks Next button', (tester) async {
      await _pumpStep(tester, outcomes: const [MicProbeOutcome.speechDetected]);

      await tester.tap(find.text('Grant Access'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('your mic is working perfectly'),
        findsOneWidget,
      );
      _expectNextEnabled(tester);
    });

    testWidgets('Try again triggers a second probe start', (tester) async {
      final probe = await _pumpStep(
        tester,
        outcomes: const [
          MicProbeOutcome.silence,
          MicProbeOutcome.speechDetected,
        ],
      );

      await tester.tap(find.text('Grant Access'));
      await tester.pumpAndSettle();
      expect(probe.startCalls, hasLength(1));

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(probe.startCalls, hasLength(2));
      // Second outcome was speechDetected → ready phase.
      expect(
        find.textContaining('your mic is working perfectly'),
        findsOneWidget,
      );
    });

    testWidgets('device picker stays hidden while only one device exists', (
      tester,
    ) async {
      await _pumpStep(
        tester,
        outcomes: const [MicProbeOutcome.silence],
        devices: const [InputDevice(id: 'a', label: 'Built-in')],
      );

      await tester.tap(find.text('Grant Access'));
      await tester.pumpAndSettle();

      expect(find.text('System default'), findsNothing);
      expect(find.text('Built-in'), findsNothing);
    });

    testWidgets('device picker appears once multiple devices are available', (
      tester,
    ) async {
      await _pumpStep(
        tester,
        outcomes: const [MicProbeOutcome.silence],
        devices: const [
          InputDevice(id: 'a', label: 'Built-in'),
          InputDevice(id: 'b', label: 'USB Headset'),
        ],
      );

      await tester.tap(find.text('Grant Access'));
      await tester.pumpAndSettle();

      expect(find.text('System default'), findsOneWidget);
    });

    testWidgets(
      'selecting a different device on non-macOS restarts the probe with that '
      'device',
      (tester) async {
        final routing = _FakeRouting(isSupportedOverride: false);
        final probe = await _pumpStep(
          tester,
          outcomes: const [
            MicProbeOutcome.silence,
            MicProbeOutcome.speechDetected,
          ],
          devices: const [
            InputDevice(id: 'a', label: 'Built-in'),
            InputDevice(id: 'b', label: 'USB Headset'),
          ],
          routing: routing,
        );

        await tester.tap(find.text('Grant Access'));
        await tester.pumpAndSettle();
        expect(probe.startCalls.first, isNull); // initial: system default

        // Open the dropdown via the picker chip.
        await tester.tap(find.text('System default'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('USB Headset').last);
        await tester.pumpAndSettle();

        expect(probe.startCalls, hasLength(2));
        expect(probe.startCalls.last?.id, 'b');
        // routing.setDefaultInputDevice must NOT be touched off-macOS.
        expect(routing.setCalls, isEmpty);
      },
    );

    testWidgets(
      'picker is visible in idle state on macOS (loaded via routing service)',
      (tester) async {
        final routing = _FakeRouting(
          isSupportedOverride: true,
          currentDefault: 'system-default-uid',
          devices: const [
            InputDevice(id: 'built-in', label: 'Built-in'),
            InputDevice(id: 'usb', label: 'USB Headset'),
          ],
        );
        await _pumpStep(tester, outcomes: const [], routing: routing);

        // Picker shows up before the user ever taps Grant.
        expect(find.text('System default'), findsOneWidget);
        // Grant button is still the primary CTA.
        expect(find.text('Grant Access'), findsOneWidget);
      },
    );

    testWidgets(
      'device selection in idle state does NOT auto-start the probe',
      (tester) async {
        final routing = _FakeRouting(
          isSupportedOverride: true,
          currentDefault: 'system-default-uid',
          devices: const [
            InputDevice(id: 'built-in', label: 'Built-in'),
            InputDevice(id: 'usb', label: 'USB Headset'),
          ],
        );
        final probe = await _pumpStep(
          tester,
          outcomes: const [MicProbeOutcome.speechDetected],
          routing: routing,
        );

        // Pick a device before granting permission.
        await tester.tap(find.text('System default'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('USB Headset').last);
        await tester.pumpAndSettle();

        // No probe started yet — we deliberately don't fire TCC behind the
        // user's back.
        expect(probe.startCalls, isEmpty);

        // Routing also untouched — selection is remembered, applied on the
        // next probe run.
        expect(routing.setCalls, isEmpty);
      },
    );

    testWidgets(
      'macOS routing path captures original UID and restores it on dispose',
      (tester) async {
        final routing = _FakeRouting(
          isSupportedOverride: true,
          currentDefault: 'system-default-uid',
        );
        await _pumpStep(
          tester,
          outcomes: const [MicProbeOutcome.silence],
          devices: const [
            InputDevice(id: 'a', label: 'Built-in'),
            InputDevice(id: 'b', label: 'USB Headset'),
          ],
          routing: routing,
        );

        await tester.tap(find.text('Grant Access'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('System default'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('USB Headset').last);
        await tester.pumpAndSettle();

        // First switch must have flipped the system default to the new device
        // and the next dispose must restore the original UID.
        expect(routing.setCalls, ['b']);

        // Unmount the widget → triggers dispose → routing restore.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();

        expect(routing.setCalls.last, 'system-default-uid');
      },
    );
  });
}
