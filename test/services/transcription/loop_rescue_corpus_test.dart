import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/transcription/loop_rescue.dart';

import '../../../benchmarks/services/transcription/loop_rescue_corpus.dart';

/// Pre-registered before the first run (stated in the #572 PR text):
/// at least 90 % of the looped cases are flagged, 0 of the clean ones.
const double kPreRegisteredDetection = 0.90;

void main() {
  test('synthetic loop corpus: pre-registered share is flagged', () {
    final flagged = loopCases.where(shouldRescueLoop).length;
    final share = flagged / loopCases.length;
    expect(share, greaterThanOrEqualTo(kPreRegisteredDetection));
  });

  test('clean corpus: zero second passes', () {
    expect(cleanCases.where(shouldRescueLoop), isEmpty);
  });
}
