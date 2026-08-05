/// Unit tests for [buildOnboardingStepIds] — the pure step-sequence function.
///
/// The six-step flow is deliberately identical on every platform and build
/// variant: platform variance (Auto-Paste visibility) lives *inside* the
/// Autostart & Auto-Paste page, never in the sequence. These tests assert
/// that invariance explicitly across the injected platform/variant matrix.
///
/// Tests here do NOT pump the widget tree — [buildOnboardingStepIds] is a pure
/// function so assertions are direct list checks, which is the highest
/// possible seam for this behaviour.
library;

import 'package:flutter/material.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/onboarding/onboarding_overlay.dart';

const _platforms = [
  TargetPlatform.macOS,
  TargetPlatform.windows,
  TargetPlatform.linux,
];

void main() {
  group('buildOnboardingStepIds', () {
    test('returns exactly 6 steps on every platform and build variant', () {
      for (final platform in _platforms) {
        for (final autoPasteSupported in [true, false]) {
          final steps = buildOnboardingStepIds(
            platform: platform,
            autoPasteSupported: autoPasteSupported,
          );
          expect(
            steps,
            hasLength(6),
            reason: 'platform=$platform autoPasteSupported=$autoPasteSupported',
          );
        }
      }
    });

    test('sequence is Welcome → Privacy → Model & Hotkey → Appearance → '
        'Autostart & Auto-Paste → Try & Go on every platform', () {
      for (final platform in _platforms) {
        for (final autoPasteSupported in [true, false]) {
          final steps = buildOnboardingStepIds(
            platform: platform,
            autoPasteSupported: autoPasteSupported,
          );
          expect(
            steps,
            const [
              OnboardingStepId.welcome,
              OnboardingStepId.privacy,
              OnboardingStepId.modelAndHotkey,
              OnboardingStepId.appearance,
              OnboardingStepId.autostartAndAutoPaste,
              OnboardingStepId.tryAndGo,
            ],
            reason: 'platform=$platform autoPasteSupported=$autoPasteSupported',
          );
        }
      }
    });

    test('sequence is identical across all platform/variant combinations — '
        'no variant may be longer or shorter than any other', () {
      final reference = buildOnboardingStepIds(
        platform: TargetPlatform.linux,
        autoPasteSupported: false,
      );
      for (final platform in _platforms) {
        for (final autoPasteSupported in [true, false]) {
          expect(
            buildOnboardingStepIds(
              platform: platform,
              autoPasteSupported: autoPasteSupported,
            ),
            reference,
            reason:
                'platform=$platform autoPasteSupported=$autoPasteSupported '
                'must match the reference sequence exactly',
          );
        }
      }
    });

    test('privacy always sits right after welcome; first step is welcome and '
        'last step is tryAndGo', () {
      for (final platform in _platforms) {
        for (final autoPasteSupported in [true, false]) {
          final steps = buildOnboardingStepIds(
            platform: platform,
            autoPasteSupported: autoPasteSupported,
          );
          expect(steps.first, OnboardingStepId.welcome);
          expect(steps[1], OnboardingStepId.privacy);
          expect(steps.last, OnboardingStepId.tryAndGo);
        }
      }
    });

    test('modelAndHotkey precedes appearance, which precedes '
        'autostartAndAutoPaste, which precedes tryAndGo (the guided test '
        'recording on the final page must exercise the hotkey/mode '
        'configured on the Model & Hotkey page, not a stale default)', () {
      for (final platform in _platforms) {
        for (final autoPasteSupported in [true, false]) {
          final steps = buildOnboardingStepIds(
            platform: platform,
            autoPasteSupported: autoPasteSupported,
          );
          final modelIndex = steps.indexOf(OnboardingStepId.modelAndHotkey);
          final appearanceIndex = steps.indexOf(OnboardingStepId.appearance);
          final autostartIndex = steps.indexOf(
            OnboardingStepId.autostartAndAutoPaste,
          );
          final tryAndGoIndex = steps.indexOf(OnboardingStepId.tryAndGo);

          expect(appearanceIndex, modelIndex + 1);
          expect(autostartIndex, appearanceIndex + 1);
          expect(tryAndGoIndex, autostartIndex + 1);
        }
      }
    });
  });
}
