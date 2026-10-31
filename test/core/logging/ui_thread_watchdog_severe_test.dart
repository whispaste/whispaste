/// The severe-stall threshold that triggers a hotkey self-heal (1 s), kept
/// separate from the warning threshold (500 ms).
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/logging/ui_thread_watchdog.dart';

void main() {
  test('a stall of 1 s or less is not severe', () {
    expect(isSevereStall(const Duration(milliseconds: 562)), isFalse);
    expect(isSevereStall(const Duration(seconds: 1)), isFalse);
  });

  test('a stall above 1 s is severe, e.g. the 1685 ms stall of 19:29', () {
    expect(isSevereStall(const Duration(milliseconds: 1685)), isTrue);
    expect(isSevereStall(const Duration(seconds: 1, milliseconds: 1)), isTrue);
  });
}
