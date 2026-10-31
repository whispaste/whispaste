// Overlay preset parity guard (WP-75b, see internal-notes).
//
// The floating-button hosts on macOS, Windows and Linux sanitise the setTheme
// payload against their own whitelists before they relay it to the render
// engine. Those lists must equal the ids the Dart presets understand
// (OverlayBackground, OverlayWave). A missing id makes the host replace the
// user's choice with the default; an extra id relays a value the engine cannot
// draw. The check reads the list literals in each host source.
//
// Static check: it proves the id sets match, not that the colours render.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/overlay_design_spec.dart';

/// Native floating-button host sources and the literal that holds each list.
/// Group 1 of each pattern is the list body with quoted ids.
const _hosts = <String, _HostLists>{
  'macos': _HostLists(
    file: 'macos/Runner/FloatingButtonHost.swift',
    background: r'backgroundPresets: Set<String> = \[([^\]]*)\]',
    wave: r'wavePresets: Set<String> = \[([^\]]*)\]',
  ),
  'windows': _HostLists(
    file: 'windows/runner/floating_button_host.cpp',
    background: r'kBackgroundPresets\[\] = \{([^}]*)\}',
    wave: r'kWavePresets\[\] = \{([^}]*)\}',
  ),
  'linux': _HostLists(
    file: 'linux/runner/floating_button_host.cc',
    background: r'kBackgroundPresets\[\] = \{([^}]*)\}',
    wave: r'kWavePresets\[\] = \{([^}]*)\}',
  ),
};

class _HostLists {
  const _HostLists({
    required this.file,
    required this.background,
    required this.wave,
  });

  final String file;
  final String background;
  final String wave;
}

/// Quoted ids inside a list literal, e.g. `"marine", "amber"`.
Set<String> _quotedIds(String source, String pattern, String file) {
  final match = RegExp(pattern).firstMatch(source);
  expect(
    match,
    isNotNull,
    reason: '$file: list literal not found (pattern $pattern)',
  );
  return {
    for (final id in RegExp(r'"([^"]*)"').allMatches(match!.group(1)!))
      id.group(1)!,
  };
}

void main() {
  final dartBackground = {for (final v in OverlayBackground.values) v.value};
  final dartWave = {for (final v in OverlayWave.values) v.value};

  for (final entry in _hosts.entries) {
    final platform = entry.key;
    final lists = entry.value;

    test('$platform host accepts exactly the Dart background presets', () {
      final source = File(lists.file).readAsStringSync();
      expect(
        _quotedIds(source, lists.background, lists.file),
        dartBackground,
        reason: 'OverlayBackground ids must match ${lists.file}',
      );
    });

    test('$platform host accepts exactly the Dart wave presets', () {
      final source = File(lists.file).readAsStringSync();
      expect(
        _quotedIds(source, lists.wave, lists.file),
        dartWave,
        reason: 'OverlayWave ids must match ${lists.file}',
      );
    });
  }
}
