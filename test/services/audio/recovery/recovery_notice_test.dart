/// A recovered recording that had to be deleted is reported to the user; the
/// other outcomes stay quiet.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/audio/recovery/recording_recovery.dart';
import 'package:whispaste/services/pending_audio/pending_audio_notice.dart';

void main() {
  test('a discarded recording reports the interrupted-discarded notice', () {
    expect(
      pendingNoticeForRecovery(RecoveryOutcome.discarded),
      PendingAudioNotice.interruptedDiscarded,
    );
  });

  test('the other outcomes report nothing', () {
    for (final outcome in [
      RecoveryOutcome.recovered,
      RecoveryOutcome.noAudio,
      RecoveryOutcome.parked,
      RecoveryOutcome.failed,
    ]) {
      expect(pendingNoticeForRecovery(outcome), isNull, reason: '$outcome');
    }
  });
}
