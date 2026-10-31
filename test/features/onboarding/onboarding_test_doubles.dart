/// Shared fakes for the onboarding widget tests. Each test file pumps the
/// overlay with the same stubs for settings, microphone, hotkey, recording
/// and model downloads; keeping them here means a stub change lands once.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData;
import 'package:flutter/foundation.dart' show ValueKey;
import 'package:flutter_test/flutter_test.dart' show Finder, WidgetTester, find;
import 'package:flutter/widgets.dart' show Widget;
import 'package:record/record.dart' show InputDevice;
import 'package:whispaste/widgets/wp_text_field.dart' show WpTextField;
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/features/onboarding/mic_probe.dart';
import 'package:whispaste/features/onboarding/onboarding_mic_gate.dart';
import 'package:whispaste/features/onboarding/onboarding_overlay.dart'
    show OnboardingStepId, kOnboardingNextButtonKey;
import 'package:whispaste/features/onboarding/steps/about_step.dart';
import 'package:whispaste/features/onboarding/steps/access_mic_step.dart';
import 'package:whispaste/features/onboarding/steps/permissions_step.dart';
import 'package:whispaste/features/onboarding/steps/privacy_step.dart';
import 'package:whispaste/features/onboarding/steps/test_recording_step.dart';
import 'package:whispaste/features/onboarding/steps/trigger_step.dart';
import 'package:whispaste/features/onboarding/steps/welcome_step.dart';
import 'package:whispaste/services/hotkey_service.dart'
    show HotkeyRegistrationStatus, HotkeyRegistrationStatusController;
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/permissions/mic_permission_notifier.dart';
import 'package:whispaste/services/recording_orchestrator.dart';
import 'package:whispaste/services/stt_parakeet/parakeet_download_service.dart';

import '../../fixtures/fake_mic_recorder.dart';

class OnboardingFakeSettings extends SettingsNotifier {
  OnboardingFakeSettings(this._initial);

  final AppSettings _initial;

  @override
  Future<AppSettings> build() async => _initial;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    state = AsyncData(updater(state.value ?? _initial));
  }
}

/// Counts OS microphone requests; the answer is always "not granted".
class OnboardingCountingMicChecker implements MicPermissionChecker {
  int requests = 0;

  @override
  Future<bool> check({required bool request}) async {
    if (request) requests++;
    return false;
  }
}

class OnboardingFakeHotkey extends HotkeyRegistrationStatusController {
  @override
  HotkeyRegistrationStatus build() => HotkeyRegistrationStatus.success;
}

class OnboardingFakeOrchestrator extends RecordingOrchestrator {
  @override
  void build() {}
}

class OnboardingFakeWhisper extends ModelDownloadNotifier {
  @override
  ModelDownloadState build() =>
      const ModelDownloadState(downloadedModels: {'whisper-medium'});
}

class OnboardingFakeParakeet extends ParakeetDownloadNotifier {
  @override
  ParakeetDownloadState build() => const ParakeetDownloadState();
}

/// Microphone probe for tests that only pass through the microphone page. It
/// starts no recorder, creates no timer and no stream. [outcome] is what the
/// probe reports at once; `null` keeps the probe listening (no outcome).
/// Speech already heard. The microphone step starts its probe only once the
/// permission reads as granted, which flows that page through Next do not set
/// up; this lets them pass the step without a live probe run.
class OnboardingFixedMicSpeech extends OnboardingMicSpeechNotifier {
  @override
  bool build() => true;
}

class OnboardingFakeMicProbe extends OnboardingMicProbe {
  OnboardingFakeMicProbe({this.outcome = MicProbeOutcome.speechDetected})
    : super(recorder: FakeMicRecorder(), timeout: null);

  final MicProbeOutcome? outcome;

  @override
  Future<MicProbeOutcome> start({InputDevice? device}) => outcome == null
      ? Completer<MicProbeOutcome>().future
      : Future.value(outcome);

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<List<InputDevice>> listInputDevices() async => const [];
}

/// The step widget that shows page [id]. The pages run full bleed and draw no
/// "Step x of y" counter, so a test recognises the current page by its step.
Finder onboardingPage(OnboardingStepId id) => switch (id) {
  OnboardingStepId.welcome => find.byType(WelcomeStep),
  OnboardingStepId.about => find.byType(AboutStep),
  OnboardingStepId.access => find.byType(PermissionsStep),
  OnboardingStepId.mic => find.byType(AccessMicStep),
  OnboardingStepId.hotkey => find.byType(TriggerStep),
  OnboardingStepId.tryOut => find.byType(TestRecordingStep),
  OnboardingStepId.privacy => find.byType(PrivacyStep),
  _ => throw ArgumentError('$id is not a page of the sequence'),
};

/// Moves the overlay one page on, the way a user who sets things up later
/// does: the about page's name question is answered with its default, the
/// Hotkey page is left through its skip, and the access page's "a permission
/// is still missing" question is confirmed.
Future<void> tapOnboardingNext(WidgetTester tester) async {
  // The split pages scroll; their actions can sit below a short window.
  Future<void> tapVisible(Finder target) async {
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  if (_aboutNameView.evaluate().isNotEmpty) {
    await tapVisible(find.byKey(kOnboardingNextButtonKey));
  }
  final skip = find.byKey(const ValueKey('onboarding-hotkey-skip'));
  await tapVisible(
    skip.evaluate().isNotEmpty ? skip : find.byKey(kOnboardingNextButtonKey),
  );
  final confirm = find.byKey(const ValueKey('confirm-dialog-confirm'));
  if (confirm.evaluate().isNotEmpty) {
    await tester.tap(confirm);
    await tester.pumpAndSettle();
  }
}

/// The about page's first view: it asks for the name in a text field.
final Finder _aboutNameView = find.descendant(
  of: find.byType(AboutStep),
  matching: find.byType(WpTextField),
);

/// The Back action of the page on screen: each full-bleed page draws its own
/// (`onboarding-<page>-back`), the model detour the shell's.

final Finder onboardingBack = find.byWidgetPredicate(
  (Widget w) =>
      w.key is ValueKey<String> &&
      RegExp(
        r'^onboarding-[a-z]+-back$',
      ).hasMatch((w.key! as ValueKey<String>).value),
);
