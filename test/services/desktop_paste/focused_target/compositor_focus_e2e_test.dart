/// V1 Wayland end to end: the focus source the app picks from the session
/// environment asks a real compositor which window has focus.
///
/// Run by test/scripts/focus_sources_e2e.sh (and, for GNOME, by
/// gnome_extension_e2e.sh with WP_GNOME_E2E_DART=1) inside a nested, headless
/// compositor with its own D-Bus session; it sets WP_FOCUS_E2E_EXPECT to
/// the identifier the focused probe window must report. Skipped otherwise.
@Tags(['compositor-e2e'])
@TestOn('linux')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/desktop_paste/focused_target/focused_target.dart';
import 'package:whispaste/services/desktop_paste/focused_target/linux_focused_target.dart';
import 'package:whispaste/services/desktop_paste/focused_target/wlr_toplevel_source.dart';

void main() {
  final env = Platform.environment;
  final expected = env['WP_FOCUS_E2E_EXPECT'];

  test(
    'the session source reports the focused probe window',
    () async {
      final desktop = detectLinuxFocusDesktop(env);
      expect(desktop.name, env['WP_FOCUS_E2E_DESKTOP']);
      // WP_FOCUS_E2E_WLR=1 asks the wlr toplevel protocol instead of the
      // compositor's own IPC (the Flatpak fallback).
      final FocusedTargetSource source = env['WP_FOCUS_E2E_WLR'] == '1'
          ? WlrToplevelFocusSource(WlrToplevelFocusSource.socketFor(env)!)
          : waylandFocusSourceFor(desktop, env)!;

      // The first lookup pays for connecting; the second is the steady state.
      await source.focusedTarget();
      final watch = Stopwatch()..start();
      final target = await source.focusedTarget();
      watch.stop();

      // ignore: avoid_print — the e2e script collects this line.
      print('FOCUS_E2E ${source.name} ${watch.elapsedMicroseconds}us $target');
      expect(target, isNotNull);
      // The primary id is what the block list and app profiles compare.
      expect(target!.id.toLowerCase(), expected!.toLowerCase());
      // The settings status line reads the same session.
      expect(await probeLinuxFocusStatus(env), LinuxFocusStatus.available);
    },
    skip: expected == null ? 'needs test/scripts/focus_sources_e2e.sh' : false,
  );
}
