// Overlay pill-width parity guard (#476).
//
// The render engine reports the animated pill width as `setPillWidth` so the
// native glass backdrop can follow the pill. macOS and Windows draw such a
// backdrop and must apply the width to it; a shell that only replies would
// leave the backdrop as wide as the window on that platform only. Linux draws
// no native backdrop: its handler is a documented no-op that merely answers.
//
// Static check: it proves each shell reads the width and hands it to its
// backdrop code, not that the backdrop renders.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _applying = <String, (String file, String pattern)>{
  'macos': (
    'macos/Runner/FloatingOverlayHost.swift',
    r'case "setPillWidth":[\s\S]{0,300}?backdropPillWidth = [^\n]*CGFloat\(w\)[\s\S]{0,400}?applyBackdrop\(',
  ),
  'windows': (
    'windows/runner/floating_overlay_host.cpp',
    r'method == "setPillWidth"[\s\S]{0,400}?window_->SetPillWidth\(last_pill_w_,',
  ),
};

void main() {
  for (final entry in _applying.entries) {
    final (file, pattern) = entry.value;
    test('${entry.key} applies setPillWidth to its glass backdrop', () {
      expect(RegExp(pattern).hasMatch(File(file).readAsStringSync()), isTrue);
    });
  }

  test('linux answers setPillWidth (no native backdrop to resize)', () {
    expect(
      RegExp(
        r'strcmp\(method, "setPillWidth"\) == 0\)[\s\S]{0,300}?fl_method_success_response_new',
      ).hasMatch(
        File('linux/runner/floating_overlay_host.cc').readAsStringSync(),
      ),
      isTrue,
    );
  });
}
