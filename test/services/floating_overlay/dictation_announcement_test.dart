/// #613: what a screen reader hears when a notice replaces an open one. The
/// rule is pure logic over id, message and detail.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/floating_overlay/dictation_notice.dart';
import 'package:whispaste/services/floating_overlay/overlay_notice.dart';

DictationNotice _notice({String detail = '', String id = 'a'}) =>
    DictationNotice(id: id, cause: 'No audio.', detail: detail);

void main() {
  test('a first notice is read whole, with its detail', () {
    expect(dictationAnnouncement(_notice()), 'No audio.');
    expect(
      dictationAnnouncement(_notice(detail: 'Suggestion: Mic')),
      'No audio. Suggestion: Mic',
    );
  });

  test('the same message again is not read again', () {
    expect(
      dictationAnnouncement(
        _notice(),
        previousId: 'a',
        previousMessage: 'No audio.',
      ),
      isNull,
    );
  });

  test('a detail that is new is read out alone', () {
    expect(
      dictationAnnouncement(
        _notice(detail: 'Suggestion: Mic'),
        previousId: 'a',
        previousMessage: 'No audio.',
      ),
      'Suggestion: Mic',
    );
  });

  test('an unchanged detail is silent, a changed one is read again', () {
    expect(
      dictationAnnouncement(
        _notice(detail: 'Suggestion: Mic'),
        previousId: 'a',
        previousMessage: 'No audio.',
        previousDetail: 'Suggestion: Mic',
      ),
      isNull,
    );
    expect(
      dictationAnnouncement(
        _notice(detail: 'Suggestion: Other'),
        previousId: 'a',
        previousMessage: 'No audio.',
        previousDetail: 'Suggestion: Mic',
      ),
      'Suggestion: Other',
    );
  });

  test('another id or another text is a new notice and read whole', () {
    expect(
      dictationAnnouncement(
        _notice(id: 'b'),
        previousId: 'a',
        previousMessage: 'No audio.',
      ),
      'No audio.',
    );
    expect(
      dictationAnnouncement(
        _notice(),
        previousId: 'a',
        previousMessage: 'Other text.',
      ),
      'No audio.',
    );
  });

  test('the body joins the second sentence and the detail on two lines', () {
    final n = DictationNotice(
      id: 'a',
      cause: 'Cause.',
      nextStep: 'Step.',
      detail: 'Line',
    );
    expect(n.body, 'Step.\nLine');
    expect(n.message, 'Cause. Step.');
  });

  test('a button name survives the trip to the overlay window', () {
    const a = OverlayNoticeAction(
      action: OverlayNoticeActionId.notice1,
      label: 'Use',
      name: 'use-microphone',
    );
    final back = OverlayNoticeAction.fromMap(a.toMap())!;
    expect(back.testName, 'use-microphone');
    expect(back.action, OverlayNoticeActionId.notice1);
    const fixed = OverlayNoticeAction(
      action: OverlayNoticeActionId.retry,
      label: 'x',
    );
    expect(fixed.testName, 'retry');
  });
}
