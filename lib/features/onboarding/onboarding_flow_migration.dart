/// Pure resume-position migration between onboarding flow versions.
///
/// The persisted `OnboardingSettings.onboardingCurrentStep` is an index into
/// the sequence of the app version that wrote it, and that sequence has
/// changed three times:
///
///  - **v0** — the pre-redesign 7/8-step flow. Platform-dependent: macOS
///    Developer-ID builds had an extra Auto-Paste step at index 3, every
///    other variant did not.
///  - **v1** — the redesign's six-step flow, identical on every platform
///    (Welcome · Privacy · Model & Hotkey · Appearance ·
///    Autostart & Auto-Paste · Try & Go).
///  - **v2** — Welcome · Privacy · Model · Hotkey · Appearance · [Auto-Paste]
///    · Try & Go. Auto-Paste is omitted from the sequence where it cannot
///    apply (see [onboardingIncludesAutoPasteStep]).
///  - **v3** — Welcome · Speech · Hotkey · Access · Try · Auto-Paste · Done
///    (ticket 02 of `internal-notes`, order as decided by
///    the maintainer on 2026-10-22). Seven steps on every platform.
///  - **v4** — the previous flow: v3 with Appearance back as its own page
///    directly before Done (maintainer decision 2026-10-22, 1a+b). Eight steps
///    on every platform; Done keeps the privacy switches open and only gets
///    shorter text, so it fits the fixed window.
///
///  - **v5** — the current flow (Onboarding v6, ticket V01): seven pages,
///    Start · About you · Access · Mic · Hotkey · Try · Privacy & Start. The closing page is merged
///    into the last page, and the model is no page any more. Stored v4
///    positions are mapped by [_kV5PositionForV4].
/// v0 and v1 positions are first translated into v2 steps, then v2 steps into
/// v4 steps, so each older sequence has exactly one meaning. v3 positions move
/// one step: Done is index 7 now, Appearance is index 6.
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
const int kOnboardingFlowVersion = 5;

/// Whether the one-time microphone-and-paste notice is due (Onboarding v6,
/// V08, E1 a). It is due for a user who finished onboarding before the current
/// flow version: a completed install whose stored flow version is still older.
/// Only a completed setup can be an existing user, so a new install is never
/// due. Showing the notice stamps [kOnboardingFlowVersion], which makes it
/// due exactly once. The stamp is harmless for a completed user, because a
/// completed install never reads its resume position again.
bool onboardingReviewHintDue({
  required bool onboardingCompleted,
  required int flowVersion,
}) => onboardingCompleted && flowVersion < kOnboardingFlowVersion;

/// Index of each v3 step in the sequence built by `buildOnboardingStepIds`.
/// Kept as plain numbers because this file must stay a widget-free unit; a
/// test pins them against the widget enum's order.
const int kV4Welcome = 0;
const int kV4Speech = 1;
const int kV4Hotkey = 2;
const int kV4Access = 3;
const int kV4Try = 4;
// Index 5 is Auto-Paste; no v2 position maps onto it (see [_v4IndexForV2]).
const int kV4Appearance = 6;
// Privacy has its own page since ADR 0032 (Maintainer 11c), directly before
// Done. Stored v4 positions of 7 therefore resume on Privacy, not on Done.
const int kV4Privacy = 7;
const int kV4Done = 8;

/// Positions of the v5 sequence (Onboarding v6, ticket V01): seven pages.
/// Start · About you · Access · Mic · Hotkey · Try · Privacy & Start. v5 never
/// shipped before About you was added, so no stored v5 position predates it. The model is not a
/// position of its own; it is opened from Start ("Anderes Modell") or from the
/// last page ("Modell laden") and is not stored.
const int kV5Welcome = 0;
const int kV5About = 1;
const int kV5Access = 2;
const int kV5Mic = 3;
const int kV5Hotkey = 4;
const int kV5Try = 5;
const int kV5Privacy = 6;

/// v4 position → v5 position. Indexed by the v4 position (0–8); anything
/// beyond falls back to Welcome. Each entry resumes on the earliest v5 page
/// that still covers what the v4 page asked for, so nothing the user has not
/// seen is skipped:
///  - Speech (1) and Welcome (0) → Start: the model moved behind the closing
///    page, Start stays the first page.
///  - Access (3, microphone then) and Auto-Paste (5) → Access: the paste
///    permission lives there now, and the microphone is only reached forward.
///  - Appearance (6) and Privacy (7) → Privacy, the nearest page still ahead.
const List<int> _kV5PositionForV4 = [
  kV5Welcome, // v4 Welcome
  kV5Welcome, // v4 Speech
  kV5Hotkey, // v4 Hotkey
  kV5Access, // v4 Access
  kV5Try, // v4 Try
  kV5Access, // v4 Auto-Paste
  kV5Privacy, // v4 Appearance
  kV5Privacy, // v4 Privacy
  kV5Privacy, // v4 Done (the closing page is the last page now)
];

/// Index of Done in the v3 sequence (Welcome · Speech · Hotkey · Access ·
/// Try · Auto-Paste · Done), which had no Appearance page.
const int kV3DoneLegacy = 6;

/// Whether the Auto-Paste page is part of the **v2** sequence for this
/// platform/build variant.
///
/// Shared by the v2 translation below. In v3 the Access step is always part
/// of the sequence; the Auto-Paste kill switch only removes its paste block.
/// `autoPasteSupported` is the deliberate App Review Guideline 2.4.5 kill
/// switch (`kAutoPasteSupported`, see `build_config.dart`).
bool onboardingIncludesAutoPasteStep({
  required TargetPlatform platform,
  required bool autoPasteSupported,
}) =>
    autoPasteSupported &&
    (platform == TargetPlatform.macOS ||
        platform == TargetPlatform.windows ||
        platform == TargetPlatform.linux);

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

/// Steps of the v1 (six-step redesign) flow — identical on every platform.
enum _V1OnboardingStep {
  welcome,
  privacy,
  modelAndHotkey,
  appearance,
  autostartAndAutoPaste,
  tryAndGo,
}

/// Steps of the v2 flow, the one the overlay rendered before ticket 02.
enum _V2OnboardingStep {
  welcome,
  privacy,
  model,
  hotkey,
  appearance,
  autoPaste,
  tryAndGo,
}

/// Ordered v0 sequence — mirrors the pre-redesign `buildOnboardingStepIds`
/// exactly (8 steps on macOS Developer-ID, 7 everywhere else).
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

/// Ordered v2 sequence for this platform/variant.
List<_V2OnboardingStep> _v2Sequence({
  required TargetPlatform platform,
  required bool autoPasteSupported,
}) => [
  _V2OnboardingStep.welcome,
  _V2OnboardingStep.privacy,
  _V2OnboardingStep.model,
  _V2OnboardingStep.hotkey,
  _V2OnboardingStep.appearance,
  if (onboardingIncludesAutoPasteStep(
    platform: platform,
    autoPasteSupported: autoPasteSupported,
  ))
    _V2OnboardingStep.autoPaste,
  _V2OnboardingStep.tryAndGo,
];

/// The v3 index a v2 step resumes at. Nothing the user has not seen is skipped:
/// privacy and appearance move to the Done page as optional content, so their
/// old positions resume at the nearest required step before them. A v2
/// Auto-Paste position resumes at Access, the earlier step, so the microphone
/// (which v2 asked for on Try) is not skipped.
int _v4IndexForV2(_V2OnboardingStep step) => switch (step) {
  _V2OnboardingStep.welcome => kV4Welcome,
  // Privacy is its own page again, directly before Done.
  _V2OnboardingStep.privacy => kV4Privacy,
  _V2OnboardingStep.model => kV4Speech,
  _V2OnboardingStep.hotkey => kV4Hotkey,
  // Appearance is its own page again, directly before Done.
  _V2OnboardingStep.appearance => kV4Appearance,
  _V2OnboardingStep.autoPaste => kV4Access,
  _V2OnboardingStep.tryAndGo => kV4Try,
};

/// Translates a persisted resume position written under [fromVersion] into
/// the index of the functionally corresponding step of the current (v3) flow:
/// 0 Welcome · 1 Speech · 2 Hotkey · 3 Access · 4 Try · 5 Auto-Paste ·
/// 6 Appearance · 7 Privacy · 8 Done.
///
/// [fromVersion] is deliberately required and has no default: with several
/// migratable source versions in the field, a default would let the call site
/// keep compiling while silently interpreting every older position through the
/// wrong table — a wrong resume page with no error and no crash.
///
/// [platform] and [autoPasteSupported] describe the v0/v1/v2 sequences a
/// stored index was written against; the v3 sequence itself does not vary.
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
  // Already current (or newer than this build knows about): nothing to
  // translate. Clamp rather than reset — a position this build cannot
  // interpret is still likelier to be right than sending the user back to
  // page 1.
  if (fromVersion >= kOnboardingFlowVersion) {
    return legacyIndex.clamp(kV5Welcome, kV5Privacy);
  }
  if (legacyIndex < 0) return kV5Welcome;
  if (fromVersion == 4) {
    return legacyIndex < _kV5PositionForV4.length
        ? _kV5PositionForV4[legacyIndex]
        : kV5Welcome;
  }
  // Older versions first resolve to the v4 sequence, then to v5.
  final v4 = _migrateToV4Index(
    legacyIndex: legacyIndex,
    fromVersion: fromVersion,
    platform: platform,
    autoPasteSupported: autoPasteSupported,
  );
  return _kV5PositionForV4[v4];
}

/// Translates a position written under [fromVersion] (0–3) into the v4
/// sequence. Kept for the older chain; [migrateLegacyOnboardingStepIndex]
/// applies the v4 → v5 table on top.
int _migrateToV4Index({
  required int legacyIndex,
  required int fromVersion,
  required TargetPlatform platform,
  required bool autoPasteSupported,
}) {
  if (legacyIndex < 0) return 0;

  // v3 had seven steps; Appearance and Privacy were not among them, so
  // everything up to Auto-Paste keeps its index and Done moves from 6 to 8.
  if (fromVersion == 3) {
    if (legacyIndex > kV3DoneLegacy) return 0;
    return legacyIndex == kV3DoneLegacy ? kV4Done : legacyIndex;
  }

  if (fromVersion == 2) {
    final v2 = _v2Sequence(
      platform: platform,
      autoPasteSupported: autoPasteSupported,
    );
    if (legacyIndex >= v2.length) return 0;
    return _v4IndexForV2(v2[legacyIndex]);
  }

  if (fromVersion == 1) {
    const v1 = _V1OnboardingStep.values;
    if (legacyIndex >= v1.length) return 0;
    final hasAutoPaste = onboardingIncludesAutoPasteStep(
      platform: platform,
      autoPasteSupported: autoPasteSupported,
    );
    final v2Step = switch (v1[legacyIndex]) {
      _V1OnboardingStep.welcome => _V2OnboardingStep.welcome,
      _V1OnboardingStep.privacy => _V2OnboardingStep.privacy,
      // The merged Model & Hotkey page resumes on its first half, so nothing
      // the user has not seen yet is skipped.
      _V1OnboardingStep.modelAndHotkey => _V2OnboardingStep.model,
      _V1OnboardingStep.appearance => _V2OnboardingStep.appearance,
      // Where the Auto-Paste page exists it is the forward-consistent landing
      // spot; where it does not (Linux under the kill switch), the Appearance
      // page is where this page's remaining content lives.
      _V1OnboardingStep.autostartAndAutoPaste =>
        hasAutoPaste
            ? _V2OnboardingStep.autoPaste
            : _V2OnboardingStep.appearance,
      _V1OnboardingStep.tryAndGo => _V2OnboardingStep.tryAndGo,
    };
    return _v4IndexForV2(v2Step);
  }

  // v0: fromVersion 0.
  final legacy = _legacySequence(
    platform: platform,
    autoPasteSupported: autoPasteSupported,
  );
  if (legacyIndex >= legacy.length) return 0;
  final v2Step = switch (legacy[legacyIndex]) {
    // Microphone merged into the Welcome page.
    _LegacyOnboardingStep.welcome ||
    _LegacyOnboardingStep.microphone => _V2OnboardingStep.welcome,
    _LegacyOnboardingStep.privacy => _V2OnboardingStep.privacy,
    _LegacyOnboardingStep.model => _V2OnboardingStep.model,
    _LegacyOnboardingStep.trigger => _V2OnboardingStep.hotkey,
    // A v0 Auto-Paste position only exists on macOS Developer-ID builds,
    // which keep the page in the v2 sequence too. The fallback is unreachable
    // in practice and stays only so this is total.
    _LegacyOnboardingStep.autoPaste =>
      onboardingIncludesAutoPasteStep(
            platform: platform,
            autoPasteSupported: autoPasteSupported,
          )
          ? _V2OnboardingStep.autoPaste
          : _V2OnboardingStep.appearance,
    _LegacyOnboardingStep.testRecording ||
    _LegacyOnboardingStep.ready => _V2OnboardingStep.tryAndGo,
  };
  return _v4IndexForV2(v2Step);
}
