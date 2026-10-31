/// Logic of [onboarding_telemetry_signals]: which onboarding state change
/// stands for which typed telemetry event, and what the about page's answers
/// send. The overlay only listens and forwards these.
library;

import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/features/onboarding/onboarding_download_status.dart';
import 'package:whispaste/features/onboarding/onboarding_overlay.dart'
    show OnboardingStepId, onboardingScreenOf;
import 'package:whispaste/features/onboarding/onboarding_telemetry_signals.dart';
import 'package:whispaste/services/onboarding_telemetry.dart';
import 'package:whispaste/services/paste/paste_capability_notifier.dart';
import 'package:whispaste/services/paste/paster.dart';
import 'package:whispaste/services/permissions/mic_permission_notifier.dart';

void main() {
  test('every page has its own screen; the model view is none', () {
    final screens = [
      for (final step in OnboardingStepId.values)
        if (step != OnboardingStepId.speech) onboardingScreenOf(step),
    ];
    expect(screens.toSet(), OnboardingScreen.values.toSet());
    expect(onboardingScreenOf(OnboardingStepId.speech), isNull);
  });

  group('download phases', () {
    OnboardingDownloadEvent? event(
      OnboardingDownloadPhase? from,
      OnboardingDownloadPhase to, {
      bool failedBefore = false,
    }) => onboardingDownloadEvent(from, to, failedBefore: failedBefore);

    test('start, done, failure and cancel', () {
      expect(
        event(OnboardingDownloadPhase.idle, OnboardingDownloadPhase.running),
        OnboardingDownloadEvent.started,
      );
      expect(
        event(OnboardingDownloadPhase.verifying, OnboardingDownloadPhase.ready),
        OnboardingDownloadEvent.done,
      );
      expect(
        event(OnboardingDownloadPhase.running, OnboardingDownloadPhase.failed),
        OnboardingDownloadEvent.failed,
      );
      expect(
        event(OnboardingDownloadPhase.running, OnboardingDownloadPhase.idle),
        OnboardingDownloadEvent.cancelled,
      );
    });

    test('a start after a failure is a retry', () {
      expect(
        event(OnboardingDownloadPhase.failed, OnboardingDownloadPhase.running),
        OnboardingDownloadEvent.retried,
      );
      expect(
        event(
          OnboardingDownloadPhase.idle,
          OnboardingDownloadPhase.running,
          failedBefore: true,
        ),
        OnboardingDownloadEvent.retried,
      );
    });

    test('progress inside a download and an installed model send nothing', () {
      expect(
        event(
          OnboardingDownloadPhase.running,
          OnboardingDownloadPhase.verifying,
        ),
        isNull,
      );
      expect(
        event(OnboardingDownloadPhase.idle, OnboardingDownloadPhase.ready),
        isNull,
      );
    });
  });

  test('microphone: asked and granted, denied, or granted before', () {
    expect(
      onboardingMicPermissionResult(
        MicPermissionStatus.requesting,
        MicPermissionStatus.granted,
      ),
      OnboardingPermissionResult.granted,
    );
    expect(
      onboardingMicPermissionResult(
        MicPermissionStatus.requesting,
        MicPermissionStatus.denied,
      ),
      OnboardingPermissionResult.denied,
    );
    expect(
      onboardingMicPermissionResult(
        MicPermissionStatus.unknown,
        MicPermissionStatus.granted,
      ),
      OnboardingPermissionResult.already,
    );
    expect(
      onboardingMicPermissionResult(
        MicPermissionStatus.unknown,
        MicPermissionStatus.requesting,
      ),
      isNull,
    );
  });

  test('paste access when the access page is left', () {
    PasteCapabilityState state(
      PasteCapabilityStatus status, {
      bool sent = false,
    }) => PasteCapabilityState(
      capability: PasteCapability(status: status),
      sentToOsGrantFlow: sent,
    );

    expect(
      onboardingPasteAccessResult(
        state(PasteCapabilityStatus.ready, sent: true),
        TargetPlatform.macOS,
      ),
      OnboardingPermissionResult.granted,
    );
    expect(
      onboardingPasteAccessResult(
        state(PasteCapabilityStatus.ready),
        TargetPlatform.linux,
      ),
      OnboardingPermissionResult.already,
    );
    expect(
      onboardingPasteAccessResult(
        state(PasteCapabilityStatus.permissionMissing),
        TargetPlatform.macOS,
      ),
      OnboardingPermissionResult.continuedWithout,
    );
    expect(
      onboardingPasteAccessResult(
        state(PasteCapabilityStatus.permissionMissing),
        TargetPlatform.windows,
      ),
      OnboardingPermissionResult.notNeeded,
    );
    expect(
      onboardingPasteAccessResult(
        const PasteCapabilityState(),
        TargetPlatform.macOS,
      ),
      isNull,
    );
  });

  group('about answers', () {
    test('roles and source map to their ids; unknown or retired ids '
        '(health) are dropped', () {
      final answers = onboardingAboutAnswers(
        const OnboardingSettings(
          userFirstName: 'Ada',
          userRoles: 'dev,health,legal,astronaut',
          userAttribution: 'github',
        ),
        systemName: 'Ada',
      );
      expect(answers.roles, {OnboardingRole.dev, OnboardingRole.legal});
      expect(answers.attribution, OnboardingAttribution.github);
      expect(answers.name, OnboardingNameEdit.kept);
    });

    test('nothing chosen is no role and source none', () {
      final answers = onboardingAboutAnswers(const OnboardingSettings());
      expect(answers.roles, isEmpty);
      expect(answers.attribution, OnboardingAttribution.none);
      expect(answers.name, OnboardingNameEdit.cleared);
    });

    test('a changed prefilled name is edited, never sent', () {
      final answers = onboardingAboutAnswers(
        const OnboardingSettings(userFirstName: 'Ada L.'),
        systemName: 'Ada',
      );
      expect(answers.name, OnboardingNameEdit.edited);
    });
  });
}
