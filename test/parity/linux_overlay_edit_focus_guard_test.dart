// The Linux overlay takes the keyboard focus only for the write preview's
// open edit field (#254, #2161) and gives it back before it hides.
//
// The overlay is a HUD that must never steal the focus from the paste
// target: a focusable overlay outside an edit session would swallow the
// user's typing and the paste. The native logic itself is tested in
// linux/runner/overlay_edit_focus_test.cc; this guards where it is wired.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final window = File(
    'linux/runner/floating_overlay_window.cc',
  ).readAsStringSync();
  final host = File('linux/runner/floating_overlay_host.cc').readAsStringSync();

  String body(String source, String signature) {
    final start = source.indexOf(signature);
    expect(start, isNot(-1), reason: signature);
    final end = source.indexOf('\n}\n', start);
    return source.substring(start, end);
  }

  test('the shell accepts focus only inside SetEditFocus', () {
    final on = RegExp(r'gtk_window_set_accept_focus\([^)]*TRUE\)');
    expect(on.allMatches(window), hasLength(1));
    expect(
      body(window, 'void FloatingOverlayWindow::SetEditFocus'),
      matches(on),
    );
    expect(
      body(window, 'void FloatingOverlayWindow::Create'),
      contains('gtk_window_set_accept_focus(GTK_WINDOW(window_), FALSE)'),
    );
  });

  test('edit focus needs a supported session and an open field', () {
    expect(
      body(window, 'void FloatingOverlayWindow::SetEditFocus'),
      contains('if (focus && !EditFocusSupported()) return;'),
    );
    expect(
      host,
      matches(
        RegExp(
          r'OverlayWantsEditFocus\(overlay_window_->EditFocusSupported\(\), '
          r'visible,\s*SnapshotEditOpen\(args\)\)',
        ),
      ),
    );
  });

  test('the focus is given back before the shell hides', () {
    expect(
      host,
      matches(
        RegExp(
          r'overlay_window_->SetEditFocus\(false\);\s*'
          r'overlay_window_->Hide\(\);',
        ),
      ),
    );
  });
}
