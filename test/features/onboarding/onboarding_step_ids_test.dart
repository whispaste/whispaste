/// Unit tests for [buildOnboardingStepIds] — the pure step-sequence function.
///
/// These tests assert the two critical branches driven by [kAutoPasteSupported]:
///
/// - Developer-ID build (autoPasteSupported == true) on macOS: the
///   [OnboardingStepId.autoPaste] step is included between microphone and model.
/// - MAS build (autoPasteSupported == false) on macOS: the autoPaste step is
///   fully absent; the remaining steps are intact.
///
/// Tests here do NOT pump the widget tree — [buildOnboardingStepIds] is a pure
/// function so assertions are direct list-membership checks, which is the
/// highest possible seam for this behaviour.
library;

import 'package:flutter/material.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/onboarding/onboarding_overlay.dart';

void main() {
  group('buildOnboardingStepIds', () {
    group('macOS Developer-ID build (autoPasteSupported: true)', () {
      late List<OnboardingStepId> steps;

      setUp(() {
        steps = buildOnboardingStepIds(
          platform: TargetPlatform.macOS,
          autoPasteSupported: true,
        );
      });

      test('includes the autoPaste step', () {
        expect(
          steps,
          contains(OnboardingStepId.autoPaste),
          reason:
              'Dev-ID build must guide the user through the Auto-Paste '
              'permission (Accessibility/TCC).',
        );
      });

      test('includes the microphone step', () {
        expect(steps, contains(OnboardingStepId.microphone));
      });

      test('returns 5 steps in total', () {
        expect(steps, hasLength(5));
      });

      test('autoPaste step appears after microphone and before model', () {
        final micIndex = steps.indexOf(OnboardingStepId.microphone);
        final autoPasteIndex = steps.indexOf(OnboardingStepId.autoPaste);
        final modelIndex = steps.indexOf(OnboardingStepId.model);

        expect(autoPasteIndex, greaterThan(micIndex));
        expect(autoPasteIndex, lessThan(modelIndex));
      });
    });

    group('macOS MAS build (autoPasteSupported: false)', () {
      late List<OnboardingStepId> steps;

      setUp(() {
        steps = buildOnboardingStepIds(
          platform: TargetPlatform.macOS,
          autoPasteSupported: false,
        );
      });

      test('omits the autoPaste step entirely', () {
        expect(
          steps,
          isNot(contains(OnboardingStepId.autoPaste)),
          reason:
              'MAS build must not present steps that are unavailable in '
              'the sandboxed variant.',
        );
      });

      test('still includes the microphone step', () {
        expect(steps, contains(OnboardingStepId.microphone));
      });

      test('returns 4 steps in total', () {
        expect(steps, hasLength(4));
      });
    });

    group('non-macOS platforms (autoPasteSupported: true)', () {
      test('Windows: omits autoPaste regardless of autoPasteSupported', () {
        final steps = buildOnboardingStepIds(
          platform: TargetPlatform.windows,
          autoPasteSupported: true,
        );
        expect(steps, isNot(contains(OnboardingStepId.autoPaste)));
        expect(steps, hasLength(4));
      });

      test('Linux: omits autoPaste regardless of autoPasteSupported', () {
        final steps = buildOnboardingStepIds(
          platform: TargetPlatform.linux,
          autoPasteSupported: true,
        );
        expect(steps, isNot(contains(OnboardingStepId.autoPaste)));
        expect(steps, hasLength(4));
      });
    });

    test('step order is always welcome → microphone → … → model → ready', () {
      for (final platform in [
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      ]) {
        for (final autoPasteSupported in [true, false]) {
          final steps = buildOnboardingStepIds(
            platform: platform,
            autoPasteSupported: autoPasteSupported,
          );
          expect(
            steps.first,
            OnboardingStepId.welcome,
            reason: 'First step must always be welcome',
          );
          expect(
            steps.last,
            OnboardingStepId.ready,
            reason: 'Last step must always be ready',
          );
          expect(
            steps.indexOf(OnboardingStepId.microphone),
            lessThan(steps.indexOf(OnboardingStepId.model)),
          );
        }
      }
    });
  });
}
