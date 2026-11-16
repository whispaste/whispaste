/// Logic tests for [onboardingReadiness], the single source of the try-out
/// page's readiness list and the closing page's model action (#186).
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/features/onboarding/onboarding_download_status.dart';
import 'package:whispaste/features/onboarding/onboarding_readiness.dart';

void main() {
  const speechFor = {
    PracticeGate.open: SpeechReadiness.ready,
    PracticeGate.loading: SpeechReadiness.loading,
    PracticeGate.failed: SpeechReadiness.failed,
    PracticeGate.missing: SpeechReadiness.missing,
  };

  group('every combination of model, microphone and paste', () {
    for (final gate in PracticeGate.values) {
      for (final micMissing in [false, true]) {
        for (final autoPaste in [false, true]) {
          for (final pasteCapable in [false, true]) {
            test('gate=${gate.name} micMissing=$micMissing '
                'autoPaste=$autoPaste pasteCapable=$pasteCapable', () {
              final r = onboardingReadiness(
                gate: gate,
                fraction: 0.4,
                micMissing: micMissing,
                autoPaste: autoPaste,
                pasteCapable: pasteCapable,
                modelUsable: true,
              );

              expect(r.speech, speechFor[gate]);
              expect(
                r.mic,
                micMissing ? MicReadiness.missing : MicReadiness.ready,
              );
              expect(
                r.paste,
                !autoPaste
                    ? PasteReadiness.off
                    : pasteCapable
                    ? PasteReadiness.automatic
                    : PasteReadiness.clipboardOnly,
              );
              // Only the model locks the field; the paste row never blocks.
              expect(r.practiceUnlocked, gate == PracticeGate.open);
              expect(r.canPractice, gate == PracticeGate.open && !micMissing);
            });
          }
        }
      }
    }
  });

  test('the closing page needs a model exactly when none is usable', () {
    for (final gate in PracticeGate.values) {
      for (final usable in [false, true]) {
        final r = onboardingReadiness(
          gate: gate,
          micMissing: false,
          autoPaste: true,
          pasteCapable: true,
          modelUsable: usable,
        );
        expect(r.completionNeedsModel, !usable, reason: gate.name);
      }
    }
  });

  test('the download fraction is kept within 0..1', () {
    OnboardingReadiness at(double f) => onboardingReadiness(
      gate: PracticeGate.loading,
      fraction: f,
      micMissing: false,
      autoPaste: true,
      pasteCapable: true,
      modelUsable: true,
    );
    expect(at(-1).speechFraction, 0);
    expect(at(0.4).speechFraction, 0.4);
    expect(at(2).speechFraction, 1);
  });
}
