/// The shared display window for the review and support nudges.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/prompt_display_arbiter.dart';

void main() {
  test('a second prompt is refused while the first one is open', () {
    final arbiter = PromptDisplayArbiter();

    expect(arbiter.tryClaim(PromptOwner.review, close: () {}), isTrue);
    expect(arbiter.tryClaim(PromptOwner.support, close: () {}), isFalse);
  });

  test('at most one nudge per session, even after the first one closed', () {
    final arbiter = PromptDisplayArbiter();

    expect(arbiter.tryClaim(PromptOwner.support, close: () {}), isTrue);
    arbiter.release(PromptOwner.support);

    expect(arbiter.tryClaim(PromptOwner.review, close: () {}), isFalse);
  });

  test('releasing with the wrong owner keeps the window held', () {
    final arbiter = PromptDisplayArbiter();
    arbiter.tryClaim(PromptOwner.review, close: () {});

    arbiter.release(PromptOwner.support);

    expect(arbiter.tryClaim(PromptOwner.support, close: () {}), isFalse);
  });

  test('closeOpenPrompt invokes the open prompt close and nothing else', () {
    final arbiter = PromptDisplayArbiter();
    var closed = 0;

    arbiter.closeOpenPrompt();
    expect(closed, 0);

    arbiter.tryClaim(PromptOwner.support, close: () => closed++);
    arbiter.closeOpenPrompt();

    expect(closed, 1);
  });
}
