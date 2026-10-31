/// Unit tests for [buildOnboardingStepIds] — the pure page sequence of
/// Onboarding v6 (ticket V01 of `internal-notes`).
///
/// Seven pages, the same on every platform and build variant. The model is not
/// part of the sequence: it is reached from Start ("Anderes Modell") or from
/// the last page ("Modell laden") only.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/onboarding/onboarding_overlay.dart';

void main() {
  group('buildOnboardingStepIds', () {
    test(
      'is Start, About you, Access, Mic, Hotkey, Try and Privacy & Start',
      () {
        expect(buildOnboardingStepIds(), const [
          OnboardingStepId.welcome,
          OnboardingStepId.about,
          OnboardingStepId.access,
          OnboardingStepId.mic,
          OnboardingStepId.hotkey,
          OnboardingStepId.tryOut,
          OnboardingStepId.privacy,
        ]);
      },
    );

    test('keeps the model page and the removed pages out of the sequence', () {
      final steps = buildOnboardingStepIds();
      expect(steps, isNot(contains(OnboardingStepId.speech)));
      expect(steps.map((s) => s.name), isNot(contains('appearance')));
      expect(steps.map((s) => s.name), isNot(contains('autoPaste')));
    });

    test('welcome is first and privacy is last; there are no duplicates', () {
      final steps = buildOnboardingStepIds();
      expect(steps.first, OnboardingStepId.welcome);
      expect(steps.last, OnboardingStepId.privacy);
      expect(steps.toSet(), hasLength(steps.length));
    });
  });
}
