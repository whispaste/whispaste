/// Pure resume-position migration from the legacy 7/8-step onboarding flow
/// to the current five-step flow.
///
/// The persisted `OnboardingSettings.onboardingCurrentStep` written by app
/// versions before the five-step redesign is an index into a
/// **platform-dependent** legacy sequence (macOS Developer-ID builds had an
/// extra Auto-Paste step at index 3; every other variant did not). Translating
/// that index therefore needs the same injection as the step-sequence builder
/// — platform and Auto-Paste support — not just the bare number.
///
/// The translation is applied exactly once, guarded by
/// `OnboardingSettings.onboardingFlowVersion` (see [kOnboardingFlowVersion]),
/// and only while `onboardingCompleted == false` (an interrupted first run).
library;

import 'package:flutter/foundation.dart' show TargetPlatform;

/// Current version of the onboarding step sequence. Stored positions carry
/// the version they were written under; anything older is translated via
/// [migrateLegacyOnboardingStepIndex] on first hydration and then stamped
/// with this value.
const int kOnboardingFlowVersion = 1;

/// Steps of the legacy (pre-five-step) onboarding flow. Kept private to this
/// migration — production code never renders these again; they only exist to
/// interpret persisted indices.
enum _LegacyOnboardingStep {
  welcome,
  privacy,
  microphone,
  autoPaste,
  model,
  trigger,
  testRecording,
  ready,
}

/// Ordered legacy sequence for the given platform/build variant — mirrors the
/// old `buildOnboardingStepIds` exactly (8 steps on macOS Developer-ID,
/// 7 everywhere else).
List<_LegacyOnboardingStep> _legacySequence({
  required TargetPlatform platform,
  required bool autoPasteSupported,
}) {
  final isMacOs = platform == TargetPlatform.macOS;
  return [
    _LegacyOnboardingStep.welcome,
    _LegacyOnboardingStep.privacy,
    _LegacyOnboardingStep.microphone,
    if (isMacOs && autoPasteSupported) _LegacyOnboardingStep.autoPaste,
    _LegacyOnboardingStep.model,
    _LegacyOnboardingStep.trigger,
    _LegacyOnboardingStep.testRecording,
    _LegacyOnboardingStep.ready,
  ];
}

/// Translates a persisted legacy resume position into the index of the
/// functionally corresponding step of the five-step flow
/// (0 Welcome · 1 Privacy · 2 Model & Hotkey · 3 Autostart & Auto-Paste ·
/// 4 Try & Go — identical on every platform).
///
/// Out-of-range positions (negative, or beyond the legacy sequence the
/// index was written against) fall back to `0` — restarting at Welcome is
/// the safe default when no correspondence exists.
int migrateLegacyOnboardingStepIndex({
  required int legacyIndex,
  required TargetPlatform platform,
  required bool autoPasteSupported,
}) {
  final legacy = _legacySequence(
    platform: platform,
    autoPasteSupported: autoPasteSupported,
  );
  if (legacyIndex < 0 || legacyIndex >= legacy.length) return 0;
  return switch (legacy[legacyIndex]) {
    // Microphone merged into the Welcome page.
    _LegacyOnboardingStep.welcome || _LegacyOnboardingStep.microphone => 0,
    _LegacyOnboardingStep.privacy => 1,
    // Model and Trigger merged into one page.
    _LegacyOnboardingStep.model || _LegacyOnboardingStep.trigger => 2,
    _LegacyOnboardingStep.autoPaste => 3,
    // Test recording and the final Ready content merged into the last page.
    _LegacyOnboardingStep.testRecording || _LegacyOnboardingStep.ready => 4,
  };
}
