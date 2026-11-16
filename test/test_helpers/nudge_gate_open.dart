/// Test override for the central nudge gate: no dictation is running and the
/// last app input is far in the past, so nudges open without waiting 30 s.
library;

import 'package:flutter_riverpod/misc.dart' show Override;

import 'package:whispaste/services/nudge_gate.dart';

Override nudgeGateOpenOverride() {
  final gate = NudgeGate(clock: DateTime.now, isDictationBusy: () => false)
    ..noteInput(DateTime(2000));
  return nudgeGateProvider.overrideWithValue(gate);
}
