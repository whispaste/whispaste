/// Pure-Dart tests for the shared post-recording prompt delay decision
/// function used by both the review prompt and support prompt watchers.
///
/// Proves the timing decoupling required by growth-reliability-conversion
/// issue 09: neither prompt is considered eligible to show within 1 second
/// of a recording completing.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/prompt_timing.dart';

void main() {
  test('does not consider the delay elapsed 1 second after completion', () {
    expect(isPromptDelayElapsed(const Duration(seconds: 1)), isFalse);
  });

  test('does not consider the delay elapsed just before the threshold', () {
    expect(
      isPromptDelayElapsed(
        kPostRecordingPromptDelay - const Duration(milliseconds: 1),
      ),
      isFalse,
    );
  });

  test('considers the delay elapsed once kPostRecordingPromptDelay has '
      'passed', () {
    expect(isPromptDelayElapsed(kPostRecordingPromptDelay), isTrue);
  });

  test('the shared delay is materially longer than 1 second', () {
    expect(kPostRecordingPromptDelay > const Duration(seconds: 1), isTrue);
  });
}
