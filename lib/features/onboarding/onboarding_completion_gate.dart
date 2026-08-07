/// Session-scoped completion-gate state for the final onboarding page.
///
/// The "Los geht's" CTA (owned by the onboarding shell) is gated on TWO
/// independent conditions:
///  1. no confirmed hotkey conflict ([hotkeyRegistrationStatusProvider] —
///     pre-existing residual gate, untouched here), AND
///  2. a successful test recording with recognised speech — proven by a
///     non-empty transcript arriving at the sandbox sink — OR the explicit
///     "continue without a microphone" escape hatch.
///
/// The escape hatch bypasses ONLY the microphone condition, never the
/// hotkey-conflict condition (PRD: "Zwei Abschluss-Gates auf Schritt 5").
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

/// Latches to `true` when the user takes the deliberately restrained
/// "continue without a microphone" escape hatch on the final page.
class OnboardingMicBypassNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void activate() => state = true;
}

final onboardingMicBypassProvider =
    NotifierProvider<OnboardingMicBypassNotifier, bool>(
      OnboardingMicBypassNotifier.new,
    );
