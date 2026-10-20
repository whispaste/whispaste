/// Onboarding beat clips: the Windows recording (beat 1) shows only on
/// Windows; beat 2 (WhisPaste's own UI) shows everywhere. Beat 3 has no clip
/// at all: it is a self-drawn illustration (UX-016), so it never counts as a
/// clip for any platform.
library;

import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/onboarding/steps/welcome_step.dart';

Future<void> _onPlatform(TargetPlatform platform, void Function() body) async {
  debugDefaultTargetPlatformOverride = platform;
  try {
    body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

void main() {
  testWidgets('Windows shows the Notepad and app-UI clips; beat 3 is drawn', (
    tester,
  ) async {
    await _onPlatform(TargetPlatform.windows, () {
      expect(
        [for (var i = 0; i < 3; i++) onboardingBeatClipFitsPlatform(i)],
        [true, true, false],
      );
    });
  });

  testWidgets('macOS shows only the app-UI beat, never the Windows clip', (
    tester,
  ) async {
    await _onPlatform(TargetPlatform.macOS, () {
      expect(
        [for (var i = 0; i < 3; i++) onboardingBeatClipFitsPlatform(i)],
        [false, true, false],
      );
    });
  });

  testWidgets('Linux shows only the app-UI beat, never the Windows clip', (
    tester,
  ) async {
    await _onPlatform(TargetPlatform.linux, () {
      expect(
        [for (var i = 0; i < 3; i++) onboardingBeatClipFitsPlatform(i)],
        [false, true, false],
      );
    });
  });
}
