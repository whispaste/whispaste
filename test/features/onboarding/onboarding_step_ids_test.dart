/// Unit tests for [buildOnboardingStepIds] — the pure step-sequence function.
///
/// The flow is seven steps on macOS and Windows and six on Linux: the
/// Auto-Paste page is omitted from the *sequence* where it cannot apply,
/// rather than rendered as a page with nothing on it. That difference is the
/// single piece of platform variance in the flow, and these tests pin both
/// sides of it — the difference itself, and the fact that nothing else about
/// the order varies.
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

List<OnboardingStepId> _steps(TargetPlatform platform, bool autoPaste) =>
    buildOnboardingStepIds(platform: platform, autoPasteSupported: autoPaste);

void main() {
  group('buildOnboardingStepIds', () {
    test('macOS and Windows run seven steps, Linux six', () {
      expect(_steps(TargetPlatform.macOS, true), hasLength(7));
      expect(_steps(TargetPlatform.windows, true), hasLength(7));
      expect(
        _steps(TargetPlatform.linux, true),
        hasLength(6),
        reason: 'Linux has no paste controller wired — no Auto-Paste page',
      );
    });

    test('sequence is Welcome → Privacy → Model → Hotkey → Appearance → '
        '[Auto-Paste] → Try & Go', () {
      expect(_steps(TargetPlatform.macOS, true), const [
        OnboardingStepId.welcome,
        OnboardingStepId.privacy,
        OnboardingStepId.model,
        OnboardingStepId.hotkey,
        OnboardingStepId.appearance,
        OnboardingStepId.autoPaste,
        OnboardingStepId.tryAndGo,
      ]);
      expect(_steps(TargetPlatform.linux, true), const [
        OnboardingStepId.welcome,
        OnboardingStepId.privacy,
        OnboardingStepId.model,
        OnboardingStepId.hotkey,
        OnboardingStepId.appearance,
        OnboardingStepId.tryAndGo,
      ]);
    });

    test('the Auto-Paste page is omitted from the sequence entirely where it '
        'cannot apply — never included as an empty page', () {
      // Linux: no paste controller, at any kill-switch setting.
      for (final autoPaste in [true, false]) {
        expect(
          _steps(TargetPlatform.linux, autoPaste),
          isNot(contains(OnboardingStepId.autoPaste)),
          reason: 'linux autoPasteSupported=$autoPaste',
        );
      }
      // The App Review Guideline 2.4.5 kill switch removes it everywhere.
      for (final platform in _platforms) {
        expect(
          _steps(platform, false),
          isNot(contains(OnboardingStepId.autoPaste)),
          reason: '$platform under the kill switch',
        );
        expect(_steps(platform, false), hasLength(6));
      }
    });

    test('every other step is present on every platform and build variant — '
        'Auto-Paste is the only thing that varies', () {
      for (final platform in _platforms) {
        for (final autoPaste in [true, false]) {
          final steps = _steps(platform, autoPaste);
          final reason = 'platform=$platform autoPasteSupported=$autoPaste';
          for (final id in OnboardingStepId.values) {
            if (id == OnboardingStepId.autoPaste) continue;
            expect(steps, contains(id), reason: '$id missing — $reason');
          }
          // Order is invariant even where the length is not: dropping the
          // Auto-Paste entry must not reshuffle anything around it.
          expect(
            steps.where((s) => s != OnboardingStepId.autoPaste).toList(),
            const [
              OnboardingStepId.welcome,
              OnboardingStepId.privacy,
              OnboardingStepId.model,
              OnboardingStepId.hotkey,
              OnboardingStepId.appearance,
              OnboardingStepId.tryAndGo,
            ],
            reason: reason,
          );
        }
      }
    });

    test('privacy always sits right after welcome; first step is welcome and '
        'last step is tryAndGo', () {
      for (final platform in _platforms) {
        for (final autoPaste in [true, false]) {
          final steps = _steps(platform, autoPaste);
          expect(steps.first, OnboardingStepId.welcome);
          expect(steps[1], OnboardingStepId.privacy);
          expect(steps.last, OnboardingStepId.tryAndGo);
        }
      }
    });

    test('model precedes hotkey, which precedes appearance, and tryAndGo is '
        'last (the guided test recording on the final page must exercise the '
        'hotkey/mode configured earlier, not a stale default)', () {
      for (final platform in _platforms) {
        for (final autoPaste in [true, false]) {
          final steps = _steps(platform, autoPaste);
          final model = steps.indexOf(OnboardingStepId.model);
          final hotkey = steps.indexOf(OnboardingStepId.hotkey);
          final appearance = steps.indexOf(OnboardingStepId.appearance);

          expect(hotkey, model + 1);
          expect(appearance, hotkey + 1);
          expect(steps.indexOf(OnboardingStepId.tryAndGo), steps.length - 1);
          if (steps.contains(OnboardingStepId.autoPaste)) {
            expect(
              steps.indexOf(OnboardingStepId.autoPaste),
              appearance + 1,
              reason: 'Auto-Paste sits between Appearance and Try & Go',
            );
          }
        }
      }
    });
  });
}
