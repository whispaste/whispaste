/// Pure resume-position migration between onboarding flow versions.
///
/// The persisted `OnboardingSettings.onboardingCurrentStep` is an index into
/// the sequence of the app version that wrote it, and that sequence has
/// changed twice:
///
///  - **v0** — the pre-redesign 7/8-step flow. Platform-dependent: macOS
///    Developer-ID builds had an extra Auto-Paste step at index 3, every
///    other variant did not.
///  - **v1** — the redesign's six-step flow, identical on every platform
///    (Welcome · Privacy · Model & Hotkey · Appearance ·
///    Autostart & Auto-Paste · Try & Go).
///  - **v2** — the current flow: Model and Hotkey each get their own page,
///    the autostart toggle moves onto the Appearance page, and Auto-Paste
///    becomes a page that is *omitted from the sequence* where it cannot
///    apply (see [onboardingIncludesAutoPasteStep]). Seven steps on
///    macOS/Windows, six on Linux.
///
/// Translating an index therefore needs the version it was written under
/// plus the same injection as the step-sequence builder — platform and
/// Auto-Paste support — not just the bare number.
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
///
/// A fresh install starts at 0 (`OnboardingSettings.onboardingFlowVersion`'s
/// default) with `onboardingCurrentStep == 0`, which every mapping below
/// sends to 0 — the migration is a no-op for it, by construction rather than
/// by luck.
const int kOnboardingFlowVersion = 2;

/// Whether the Auto-Paste page is part of the sequence at all for this
/// platform/build variant.
///
/// The single source of truth for the one piece of platform variance in the
/// flow, shared by `buildOnboardingStepIds` and by this migration — Linux has
/// no paste controller wired, so it gets a genuine six-step flow rather than
/// a dead page. `autoPasteSupported` is the deliberate App Review Guideline
/// 2.4.5 kill switch (`kAutoPasteSupported`, see `build_config.dart`): if it
/// is ever flipped off, the page disappears from every platform's sequence.
bool onboardingIncludesAutoPasteStep({
  required TargetPlatform platform,
  required bool autoPasteSupported,
}) =>
    autoPasteSupported &&
    (platform == TargetPlatform.macOS || platform == TargetPlatform.windows);

/// Steps of the v0 (pre-redesign) onboarding flow. Kept private to this
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

/// Ordered v0 sequence for the given platform/build variant — mirrors the
/// pre-redesign `buildOnboardingStepIds` exactly (8 steps on macOS
/// Developer-ID, 7 everywhere else).
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

/// Steps of the v1 (six-step redesign) flow — identical on every platform.
enum _V1OnboardingStep {
  welcome,
  privacy,
  modelAndHotkey,
  appearance,
  autostartAndAutoPaste,
  tryAndGo,
}

/// Target indices of the current (v2) sequence for this platform/variant.
///
/// Named rather than derived via `indexOf` on the real sequence, because the
/// sequence builder lives with the widget shell and this file must stay a
/// pure, widget-free unit. [onboardingIncludesAutoPasteStep] is the shared
/// piece that keeps the two in step; the rest is a fixed order both sides
/// spell out.
({
  int welcome,
  int privacy,
  int model,
  int hotkey,
  int appearance,
  int? autoPaste,
  int tryAndGo,
})
_targetIndices({required bool hasAutoPaste}) => (
  welcome: 0,
  privacy: 1,
  model: 2,
  hotkey: 3,
  appearance: 4,
  autoPaste: hasAutoPaste ? 5 : null,
  tryAndGo: hasAutoPaste ? 6 : 5,
);

/// Translates a persisted resume position written under [fromVersion] into
/// the index of the functionally corresponding step of the current flow
/// (0 Welcome · 1 Privacy · 2 Model · 3 Hotkey · 4 Appearance ·
/// 5 Auto-Paste (macOS/Windows only) · last Try & Go).
///
/// [fromVersion] is deliberately required and has no default: with two
/// migratable source versions in the field, a default would let the call site
/// keep compiling while silently interpreting every v1 position through the
/// v0 table — a wrong resume page with no error and no crash.
///
/// Out-of-range positions (negative, or beyond the sequence the index was
/// written against) fall back to `0` — restarting at Welcome is the safe
/// default when no correspondence exists.
int migrateLegacyOnboardingStepIndex({
  required int legacyIndex,
  required int fromVersion,
  required TargetPlatform platform,
  required bool autoPasteSupported,
}) {
  final hasAutoPaste = onboardingIncludesAutoPasteStep(
    platform: platform,
    autoPasteSupported: autoPasteSupported,
  );
  final target = _targetIndices(hasAutoPaste: hasAutoPaste);
  if (legacyIndex < 0) return 0;

  // Already current (or newer than this build knows about): nothing to
  // translate. Clamp rather than reset — a position this build cannot
  // interpret is still likelier to be right than sending the user back to
  // page 1.
  if (fromVersion >= kOnboardingFlowVersion) {
    return legacyIndex.clamp(0, target.tryAndGo);
  }

  if (fromVersion >= 1) {
    const v1 = _V1OnboardingStep.values;
    if (legacyIndex >= v1.length) return 0;
    return switch (v1[legacyIndex]) {
      _V1OnboardingStep.welcome => target.welcome,
      _V1OnboardingStep.privacy => target.privacy,
      // The merged Model & Hotkey page split in two: resume on the first
      // half, so nothing the user has not seen yet is skipped.
      _V1OnboardingStep.modelAndHotkey => target.model,
      _V1OnboardingStep.appearance => target.appearance,
      // The merged page split apart too, but in the other direction: its
      // autostart toggle moved *onto* the Appearance page and only the
      // Auto-Paste half kept a page. Where that page exists it is the
      // forward-consistent landing spot; where it doesn't (Linux), the
      // Appearance page is now where this page's remaining content lives.
      _V1OnboardingStep.autostartAndAutoPaste =>
        target.autoPaste ?? target.appearance,
      _V1OnboardingStep.tryAndGo => target.tryAndGo,
    };
  }

  final legacy = _legacySequence(
    platform: platform,
    autoPasteSupported: autoPasteSupported,
  );
  if (legacyIndex >= legacy.length) return 0;
  return switch (legacy[legacyIndex]) {
    // Microphone merged into the Welcome page.
    _LegacyOnboardingStep.welcome ||
    _LegacyOnboardingStep.microphone => target.welcome,
    _LegacyOnboardingStep.privacy => target.privacy,
    // Model and Trigger are separate pages again, so the v0 correspondence
    // is one-to-one rather than the collapse v1 needed.
    _LegacyOnboardingStep.model => target.model,
    _LegacyOnboardingStep.trigger => target.hotkey,
    // A v0 Auto-Paste position only exists on macOS Developer-ID builds,
    // where the page is part of the current sequence too. The fallback is
    // unreachable in practice and stays only so this is total.
    _LegacyOnboardingStep.autoPaste => target.autoPaste ?? target.appearance,
    // Test recording and the final Ready content merged into the last page.
    _LegacyOnboardingStep.testRecording ||
    _LegacyOnboardingStep.ready => target.tryAndGo,
  };
}
