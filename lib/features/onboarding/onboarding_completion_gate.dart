/// Session-scoped completion-gate state for the final onboarding page.
///
/// Onboarding v6 (flow version 5): the completion CTA is gated ONLY by a
/// confirmed hotkey conflict ([hotkeyRegistrationStatusProvider]). The
/// microphone and test-recording providers below are no longer part of the
/// gate; the test-recording step still reads them for its own status display
/// until that page is rebuilt (ticket V08). ReadyStep, which read them before,
/// was removed in v6.
///
/// Both states live for the duration of the app session (plain
/// [Notifier]s, no persistence) — a completed onboarding never reads them
/// again, and an interrupted onboarding intentionally re-asks for the proof
/// on the next launch.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Latches to `true` once a test recording delivered a non-empty transcript
/// to the sandbox sink — the proof that microphone capture and speech
/// recognition actually work on this machine.
class OnboardingTestRecordingSucceededNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void markSucceeded() => state = true;
}

final onboardingTestRecordingSucceededProvider =
    NotifierProvider<OnboardingTestRecordingSucceededNotifier, bool>(
      OnboardingTestRecordingSucceededNotifier.new,
    );
