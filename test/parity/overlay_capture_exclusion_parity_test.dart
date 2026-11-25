// Overlay capture-exclusion parity guard (overlay F, #194).
//
// "In Bildschirmfreigaben und Screenshots verbergen" reaches each shell as
// `setCaptureExcluded{excluded}`. macOS and Windows keep the overlay window
// out of captures and must apply the value again to every window they create
// (first show, stuck-panel rebuild, render-engine reboot): a rebuilt window
// that forgot it would show up in the next screen share. Linux has no such
// switch and must still answer the call, so Dart never sees an error there.
//
// Static check: it proves the handler, the system call and the re-apply on
// window creation exist per platform, not that a capture leaves the window
// out (that is the manual check with a real recording on Mac and Windows).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Strips `//` line comments, so a name in a comment does not count.
String _code(String path) => File(
  path,
).readAsLinesSync().map((l) => l.replaceFirst(RegExp(r'//.*$'), '')).join('\n');

void main() {
  test('every Dart controller sends setCaptureExcluded', () {
    for (final platform in ['macos', 'windows', 'linux']) {
      final dart = _code(
        'lib/services/floating_overlay/'
        '${platform}_floating_overlay_controller.dart',
      );
      expect(
        dart,
        contains("invokeMethod('setCaptureExcluded'"),
        reason: '$platform controller must send the switch',
      );
      expect(dart, contains('OverlayCaptureExclusion'), reason: platform);
    }
  });

  test('macOS sets sharingType on every panel it creates', () {
    final swift = _code('macos/Runner/FloatingOverlayHost.swift');
    expect(swift, contains('case "setCaptureExcluded":'));
    expect(swift, contains('sharingType = captureExcluded ? .none'));
    final creations = RegExp(
      // Plain property settings may sit between (#2165 sets
      // acceptsKeyboard); nothing may show the panel before the re-apply.
      r'let p = FloatingOverlayPanel\([^)]*\)\s*\n\s*panel = p\s*\n'
      r'(?:\s*p\.\w+ = \w+\s*\n)*\s*applyCaptureExclusion\(\)',
    ).allMatches(swift).length;
    final panels = RegExp(r'FloatingOverlayPanel\(width:').allMatches(swift);
    expect(creations, panels.length, reason: 'each new panel re-applies it');
  });

  test('Windows sets the display affinity on every shell it creates', () {
    final cpp = _code('windows/runner/floating_overlay_host.cpp');
    expect(cpp, contains('method == "setCaptureExcluded"'));
    expect(cpp, contains('WDA_EXCLUDEFROMCAPTURE'));
    expect(cpp, contains('SetWindowDisplayAffinity('));
    expect(
      RegExp(
        r'window_ = std::move\(shell\);\s*\n\s*ApplyCaptureExclusion\(\);',
      ).hasMatch(cpp),
      isTrue,
      reason: 'the only shell creation must re-apply it',
    );
    expect(RegExp(r'window_ = std::move\(').allMatches(cpp).length, 1);
  });

  test('Linux answers the call without applying anything', () {
    final cc = _code('linux/runner/floating_overlay_host.cc');
    expect(
      RegExp(
        r'strcmp\(method, "setCaptureExcluded"\) == 0\)[\s\S]{0,400}?'
        r'fl_value_new_bool\(FALSE\)',
      ).hasMatch(cc),
      isTrue,
    );
  });
}
