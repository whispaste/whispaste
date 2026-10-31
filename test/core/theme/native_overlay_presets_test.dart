// Guard for the preset IDs copied into the three native floating-button hosts
// (WP-75, DEV-177). The hosts sanitise setTheme against their own lists, so a
// preset added in Dart but missing there would silently fall back to marine
// or cyan. The lists are read from the source files and compared to the enums.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/overlay_design_spec.dart';

/// Matches [code] in a source file whatever whitespace or line breaks the
/// file uses between its characters, so a reformatted native host (wrapped
/// call, extra spaces) still counts. Quotes and punctuation stay exact.
RegExp _tolerant(String code) => RegExp(
  code.replaceAll(RegExp(r'\s+'), '').split('').map(RegExp.escape).join(r'\s*'),
);

/// Quoted IDs inside the first `{...}` or `[...]` after [anchor].
List<String> _idsAfter(String source, String anchor) {
  final hit = _tolerant(anchor).firstMatch(source);
  expect(hit, isNotNull, reason: 'anchor "$anchor" not found');
  // Start after the anchor, so the `[]` of `kName[]` is not taken as the list.
  final open = source.indexOf(RegExp(r'[\{\[]'), hit!.end);
  final close = source.indexOf(RegExp(r'[\}\]]'), open);
  final body = source.substring(open + 1, close);
  return RegExp(
    r'"([a-z]+)"',
  ).allMatches(body).map((m) => m.group(1)!).toList();
}

void main() {
  final expectedBackground = OverlayBackground.values.map((e) => e.value);
  final expectedWave = OverlayWave.values.map((e) => e.value);

  group('native hosts carry the Dart preset IDs', () {
    test('windows: kBackgroundPresets / kWavePresets and defaults', () {
      final src = File(
        'windows/runner/floating_button_host.cpp',
      ).readAsStringSync();
      expect(
        _idsAfter(src, 'kBackgroundPresets[]'),
        unorderedEquals(expectedBackground),
      );
      expect(_idsAfter(src, 'kWavePresets[]'), unorderedEquals(expectedWave));
      expect(
        src,
        matches(_tolerant('GetString(*map, "background", "marine")')),
      );
      expect(src, matches(_tolerant('GetString(*map, "wave", "cyan")')));
    });

    test('linux: kBackgroundPresets / kWavePresets and defaults', () {
      final src = File(
        'linux/runner/floating_button_host.cc',
      ).readAsStringSync();
      expect(
        _idsAfter(src, 'kBackgroundPresets[]'),
        unorderedEquals(expectedBackground),
      );
      expect(_idsAfter(src, 'kWavePresets[]'), unorderedEquals(expectedWave));
      expect(src, matches(_tolerant('kBackgroundPresets, "marine"')));
      expect(src, matches(_tolerant('kWavePresets, "cyan"')));
    });

    test('macos: backgroundPresets / wavePresets and defaults', () {
      final src = File(
        'macos/Runner/FloatingButtonHost.swift',
      ).readAsStringSync();
      expect(
        _idsAfter(src, 'backgroundPresets: Set<String>'),
        unorderedEquals(expectedBackground),
      );
      expect(
        _idsAfter(src, 'wavePresets: Set<String>'),
        unorderedEquals(expectedWave),
      );
      expect(src, matches(_tolerant('} ?? "marine"')));
      expect(src, matches(_tolerant('} ?? "cyan"')));
    });
  });

  test('the defaults are the marine and cyan presets', () {
    expect(OverlayBackground.fromValue(null), OverlayBackground.marine);
    expect(OverlayWave.fromValue(null), OverlayWave.cyan);
  });
}
