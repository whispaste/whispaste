// UIA-HIS-16: a toast offering Undo after a voice correction stays long enough
// to notice a wrong correction.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/history/widgets/voice_note_button.dart';

void main() {
  test('toasts with an Undo action stay for 8 seconds (UIA-HIS-16)', () {
    expect(voiceToastDuration(hasUndo: true), const Duration(seconds: 8));
  });

  test('plain toasts keep the short 2 second duration', () {
    expect(voiceToastDuration(hasUndo: false), const Duration(seconds: 2));
  });
}
