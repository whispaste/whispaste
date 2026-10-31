/// Widget tests for the onboarding microphone page (`AccessMicStep`, V04, S3).
///
/// The level comes from the real [OnboardingMicProbe] on a [FakeMicRecorder];
/// the clock is the test clock (`tester.pump`), so the 10 s silence window is
/// exact. The page's permission check runs through the real notifier with an
/// injected platform checker.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/onboarding/mic_probe.dart';
import 'package:whispaste/features/onboarding/onboarding_mic_gate.dart';
import 'package:whispaste/features/onboarding/steps/access_mic_step.dart';
import 'package:whispaste/services/audio/amplitude_from_pcm.dart';
import 'package:whispaste/services/audio_service.dart';
import 'package:whispaste/services/microphone_selection_service.dart';
import 'package:whispaste/services/permissions/mic_permission_notifier.dart';

import '../../fixtures/fake_mic_recorder.dart';
import '../../fixtures/test_helpers.dart';
import 'onboarding_test_doubles.dart';

/// Checker whose answer the test controls. With `request: true` it grants when
/// [grantOnRequest] is set, like the operating-system dialog would.
class _ScriptedMicChecker implements MicPermissionChecker {
  _ScriptedMicChecker({required this.granted, this.grantOnRequest = false});

  bool granted;
  final bool grantOnRequest;
  int requests = 0;

  @override
  Future<bool> check({required bool request}) async {
    if (request) {
      requests++;
      if (grantOnRequest) granted = true;
    }
    return granted;
  }
}

/// A level meter the test drives: no timer and no PCM. [emit] feeds one dBFS
/// value to the probe. It lives as long as the harness, so a restarted probe
/// listens to the same meter again.
class _ScriptedMeter implements PcmLevelMeter {
  final StreamController<double> _levels = StreamController<double>.broadcast();

  void emit(double dbFs) => _levels.add(dbFs);

  @override
  Stream<double> get stream => _levels.stream;

  @override
  void addChunk(Uint8List bytes) {}

  @override
  Future<void> dispose() async {}
}

/// Feeds loud audio for about 240 ms, past the probe's sustained-speech window.
Future<void> _speak(
  WidgetTester tester,
  _ScriptedMeter meter, {
  double dbFs = -20,
}) async {
  for (var i = 0; i < 8; i++) {
    meter.emit(dbFs);
    await tester.pump(const Duration(milliseconds: 40));
  }
}

/// Every test ends by unmounting the page, so the probe stops its stream and
/// timers before the framework checks for pending timers.
void micTest(String description, WidgetTesterCallback body) {
  testWidgets(description, (tester) async {
    await body(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

class _Harness {
  _Harness({this.granted = true, this.grantOnRequest = false, this.onSkip});

  final bool granted;
  final bool grantOnRequest;
  final VoidCallback? onSkip;
  final String selected = micDefaultLabel;
  final List<String> devices = const ['Default', 'USB-Mikrofon'];

  final FakeMicRecorder recorder = FakeMicRecorder();
  final _ScriptedMeter meter = _ScriptedMeter();
  late OnboardingMicProbe probe;
  late final _ScriptedMicChecker checker = _ScriptedMicChecker(
    granted: granted,
    grantOnRequest: grantOnRequest,
  );
  final List<String> persisted = [];
}

Future<void> _pumpMicStep(
  WidgetTester tester,
  _Harness h, {
  Size size = const Size(800, 600),
  TextScaler textScaler = TextScaler.noScaling,
  bool disableAnimations = false,
  TextDirection direction = TextDirection.ltr,
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final probe = h.probe = OnboardingMicProbe(
    recorder: h.recorder,
    timeout: null,
    pollInterval: const Duration(milliseconds: 40),
    meterFactory: ({required Duration pollInterval}) => h.meter,
  );

  await tester.pumpWidget(
    makeTestable(
      MediaQuery(
        data: MediaQueryData(
          size: size,
          disableAnimations: disableAnimations,
          textScaler: textScaler,
        ),
        child: Directionality(
          textDirection: direction,
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: size.width,
              child: AccessMicStep(onSkip: h.onSkip ?? () {}, onNext: () {}),
            ),
          ),
        ),
      ),
      size: size,
      locale: locale,
      overrides: [
        settingsProvider.overrideWith(
          () => OnboardingFakeSettings(
            AppSettings.defaults.copyWithSections(
              audioInput: AppSettings.defaults.audioInput.copyWith(
                microphone: h.selected,
              ),
            ),
          ),
        ),
        micPermissionCheckerProvider.overrideWithValue(h.checker),
        onboardingMicProbeProvider.overrideWithValue(probe),
        audioInputDevicesProvider.overrideWith((ref) async => h.devices),
        microphoneSelectionServiceProvider.overrideWithValue(
          MicrophoneSelectionService(
            persistLabel: (label) async => h.persisted.add(label),
          ),
        ),
      ],
    ),
  );
  // Let the post-frame permission check and the probe start settle.
  await tester.pump();
  await tester.pump();
}

String _l10n(WidgetTester tester, String Function(L10n) pick) =>
    pick(L10n.of(tester.element(find.byType(AccessMicStep))));

void main() {
  group('Mic page: no speech (S3)', () {
    micTest('Überspringen is visible and no prompt shows before 10 s', (
      tester,
    ) async {
      final h = _Harness();
      await _pumpMicStep(tester, h);

      expect(find.bySemanticsIdentifier('onboarding-mic-skip'), findsOneWidget);
      await tester.pump(const Duration(seconds: 9));
      expect(
        find.bySemanticsIdentifier('onboarding-mic-silence-prompt'),
        findsNothing,
      );
      expect(
        find.text(_l10n(tester, (l) => l.onboardingMicHeard)),
        findsNothing,
      );
    });

    micTest('after 10 s of silence the inline prompt appears', (tester) async {
      final h = _Harness();
      await _pumpMicStep(tester, h);

      await tester.pump(kOnboardingMicSilenceTimeout);
      expect(
        find.bySemanticsIdentifier('onboarding-mic-silence-prompt'),
        findsOneWidget,
      );
      expect(
        find.text(_l10n(tester, (l) => l.onboardingMicSilence)),
        findsOneWidget,
      );
    });

    micTest('speech after the silence prompt is still heard and clears '
        'the prompt', (tester) async {
      final h = _Harness();
      await _pumpMicStep(tester, h);
      await tester.pump(kOnboardingMicSilenceTimeout);
      expect(
        find.bySemanticsIdentifier('onboarding-mic-silence-prompt'),
        findsOneWidget,
      );
      await _speak(tester, h.meter);
      await tester.pump();

      expect(find.text(_l10n(tester, (l) => l.onboardingMicHeard)), findsOne);
      expect(
        find.bySemanticsIdentifier('onboarding-mic-silence-prompt'),
        findsNothing,
      );
    });

    micTest('tapping the prompt focuses the device picker', (tester) async {
      final h = _Harness();
      await _pumpMicStep(tester, h);
      await tester.pump(kOnboardingMicSilenceTimeout);

      await tester.tap(
        find.bySemanticsIdentifier('onboarding-mic-silence-prompt'),
      );
      await tester.pump();

      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'onboardingMicDevice',
      );
    });

    micTest('the skip button calls onSkip', (tester) async {
      var skipped = 0;
      final h = _Harness(onSkip: () => skipped++);
      await _pumpMicStep(tester, h);

      await tester.tap(find.bySemanticsIdentifier('onboarding-mic-skip'));
      await tester.pump();

      expect(skipped, 1);
    });
  });

  group('Mic page: speech heard', () {
    micTest('the status line reports the heard speech and the probe '
        'does not prompt afterwards', (tester) async {
      final h = _Harness();
      await _pumpMicStep(tester, h);

      await _speak(tester, h.meter);
      await tester.pump();

      expect(find.text(_l10n(tester, (l) => l.onboardingMicHeard)), findsOne);
      await tester.pump(kOnboardingMicSilenceTimeout);
      expect(
        find.bySemanticsIdentifier('onboarding-mic-silence-prompt'),
        findsNothing,
      );
    });
  });

  group('Mic page: permission missing', () {
    micTest('one line with an action, no probe started', (tester) async {
      final h = _Harness(granted: false);
      await _pumpMicStep(tester, h);

      expect(
        find.bySemanticsIdentifier('onboarding-mic-allow'),
        findsOneWidget,
      );
      expect(
        find.text(_l10n(tester, (l) => l.onboardingMicPermissionLine)),
        findsOneWidget,
      );
      expect(
        h.recorder.lastConfig,
        isNull,
        reason: 'the probe must not open the microphone without a grant',
      );
    });

    micTest('granting from the line starts the level probe', (tester) async {
      final h = _Harness(granted: false, grantOnRequest: true);
      await _pumpMicStep(tester, h);

      await tester.tap(find.bySemanticsIdentifier('onboarding-mic-allow'));
      await tester.pump();
      await tester.pump();

      expect(h.checker.requests, 1);
      expect(h.recorder.lastConfig, isNotNull);
      expect(find.bySemanticsIdentifier('onboarding-mic-allow'), findsNothing);
    });
  });

  group('Mic page: device picker', () {
    micTest('the picker lists the system default and the devices', (
      tester,
    ) async {
      final h = _Harness();
      await _pumpMicStep(tester, h);

      expect(find.bySemanticsIdentifier('onboarding-mic-device'), findsOne);
      expect(
        find.text(_l10n(tester, (l) => l.settingsMicSystemDefault)),
        findsOneWidget,
      );
    });
  });
}
