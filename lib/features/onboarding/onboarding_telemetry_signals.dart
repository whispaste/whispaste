/// How onboarding state turns into the typed events of
/// [OnboardingTelemetry]: which page is which screen, which state change is a
/// download or permission event, and what the about page's answers send. Pure
/// functions, so the overlay only listens and forwards.
library;

import 'package:flutter/foundation.dart' show TargetPlatform;

import '../../core/config/settings_sections.dart' show OnboardingSettings;
import '../../services/onboarding_telemetry.dart';
import '../../services/paste/paste_capability_notifier.dart'
    show PasteCapabilityState;
import '../../services/paste/paster.dart' show PasteCapabilityStatus;
import '../../services/permissions/mic_permission_notifier.dart'
    show MicPermissionStatus;
import 'onboarding_download_status.dart' show OnboardingDownloadPhase;

bool _loading(OnboardingDownloadPhase? p) =>
    p == OnboardingDownloadPhase.running ||
    p == OnboardingDownloadPhase.verifying;

/// The download event a phase change stands for, or `null` for none (for
/// example running → verifying). A start after a failure is a retry.
OnboardingDownloadEvent? onboardingDownloadEvent(
  OnboardingDownloadPhase? previous,
  OnboardingDownloadPhase next, {
  required bool failedBefore,
}) {
  if (_loading(next) && !_loading(previous)) {
    return failedBefore || previous == OnboardingDownloadPhase.failed
        ? OnboardingDownloadEvent.retried
        : OnboardingDownloadEvent.started;
  }
  if (!_loading(previous)) return null;
  return switch (next) {
    OnboardingDownloadPhase.ready => OnboardingDownloadEvent.done,
    OnboardingDownloadPhase.failed => OnboardingDownloadEvent.failed,
    OnboardingDownloadPhase.idle => OnboardingDownloadEvent.cancelled,
    OnboardingDownloadPhase.running ||
    OnboardingDownloadPhase.verifying => null,
  };
}

/// The microphone permission result a status change stands for: a grant or
/// denial after the user was asked, or a grant that was already there.
OnboardingPermissionResult? onboardingMicPermissionResult(
  MicPermissionStatus? previous,
  MicPermissionStatus next,
) => switch ((previous, next)) {
  (MicPermissionStatus.requesting, MicPermissionStatus.granted) =>
    OnboardingPermissionResult.granted,
  (MicPermissionStatus.requesting, MicPermissionStatus.denied) =>
    OnboardingPermissionResult.denied,
  (MicPermissionStatus.unknown || null, MicPermissionStatus.granted) =>
    OnboardingPermissionResult.already,
  _ => null,
};

/// The paste-access result when the access page is left. Windows needs no
/// grant; elsewhere a working paste counts as granted when the user was sent
/// to the system settings and as already there otherwise.
OnboardingPermissionResult? onboardingPasteAccessResult(
  PasteCapabilityState state,
  TargetPlatform platform,
) {
  final status = state.capability?.status;
  if (platform == TargetPlatform.windows) {
    return OnboardingPermissionResult.notNeeded;
  }
  return switch (status) {
    PasteCapabilityStatus.ready =>
      state.sentToOsGrantFlow
          ? OnboardingPermissionResult.granted
          : OnboardingPermissionResult.already,
    PasteCapabilityStatus.permissionMissing =>
      OnboardingPermissionResult.continuedWithout,
    PasteCapabilityStatus.unsupported || null => null,
  };
}

/// The about page's answers as wire values: the chosen roles, the source
/// (`none` when skipped) and what happened to the prefilled first name.
({
  Set<OnboardingRole> roles,
  OnboardingAttribution attribution,
  OnboardingNameEdit name,
})
onboardingAboutAnswers(OnboardingSettings onboarding, {String? systemName}) {
  final roleIds = OnboardingRole.values.asNameMap();
  final sources = OnboardingAttribution.values.asNameMap();
  final name = onboarding.userFirstName.trim();
  return (
    roles: {
      for (final id in onboarding.userRoles.split(',')) ?roleIds[id.trim()],
    },
    attribution:
        sources[onboarding.userAttribution] ?? OnboardingAttribution.none,
    name: name.isEmpty
        ? OnboardingNameEdit.cleared
        : name == (systemName ?? '').trim()
        ? OnboardingNameEdit.kept
        : OnboardingNameEdit.edited,
  );
}
