/// State of the onboarding microphone page (Onboarding v6, ticket V04).
///
/// The page owns the live level probe; the shell reads the speech flag to hold
/// "Weiter" until the user has actually spoken into the microphone (S3).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'mic_probe.dart';

/// How long the page listens before it offers the device picker ("Nichts
/// gehört – anderes Gerät wählen?"). The page owns this timer; the probe does
/// not, so speech that comes after the prompt is still reported.
const Duration kOnboardingMicSilenceTimeout = Duration(seconds: 10);

/// Whether speech has been detected on the microphone page in this run. The
/// shell's "Weiter" stays off until this is true (outside a review or a
/// revision run).
class OnboardingMicSpeechNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void markHeard() => state = true;
}

final onboardingMicSpeechHeardProvider =
    NotifierProvider<OnboardingMicSpeechNotifier, bool>(
      OnboardingMicSpeechNotifier.new,
    );

/// The microphone probe behind the level card. Tests override it with a probe
/// built on a fake recorder and drive the clock with `tester.pump`.
final onboardingMicProbeProvider = Provider<OnboardingMicProbe>((ref) {
  final probe = OnboardingMicProbe(timeout: null);
  ref.onDispose(() => unawaited(probe.dispose()));
  return probe;
});
