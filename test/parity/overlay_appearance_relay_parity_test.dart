// Overlay appearance relay parity guard (WP-95, see .scratch/wp95-overlay-customizing/).
//
// The WP-95 options (form, wave style, fluid outline, timer, cancel glyph,
// opacity) are drawn by the shared Dart overlay view, not by the native
// shells. They reach the render engine only if every platform host relays the
// whole snapshot payload unchanged. This static check proves each host still
// relays `updateSnapshot` with the full argument map, and that the Dart map
// carries the appearance keys the hosts pass through.
//
// Static check: it proves the relay call exists per platform, not that the
// render engine draws the options (the widget tests cover that).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/overlay_customization.dart';
import 'package:whispaste/services/floating_overlay/floating_overlay_controller_interface.dart';

const _relays = <String, (String file, String pattern)>{
  'macos': (
    'macos/Runner/FloatingOverlayHost.swift',
    r'renderChannel\?\.invokeMethod\("updateSnapshot", arguments: args\)',
  ),
  'windows': (
    'windows/runner/floating_overlay_host.cpp',
    r'"updateSnapshot",\s*std::make_unique<EncodableValue>\(\*latest_snapshot_args_\)',
  ),
  'linux': (
    'linux/runner/floating_overlay_host.cc',
    r'InvokeRenderChannel\("updateSnapshot", args\)',
  ),
};

void main() {
  for (final entry in _relays.entries) {
    test('${entry.key} relays the full updateSnapshot payload', () {
      final source = File(entry.value.$1).readAsStringSync();
      expect(
        RegExp(entry.value.$2).hasMatch(source),
        isTrue,
        reason:
            '${entry.value.$1} must relay args unchanged to the render engine',
      );
    });
  }

  test('the Dart snapshot map carries every appearance key', () {
    const keys = [
      'form',
      'waveStyle',
      'waveFluid',
      'showTimer',
      'showCancel',
      'opacity',
    ];
    final map = const FloatingOverlaySnapshot(
      visible: true,
      state: OverlayVisualState.recording,
      label: '',
      appearance: OverlayAppearance(opacity: OverlayOpacity.reduced),
    ).toMap();
    for (final key in keys) {
      expect(map.containsKey(key), isTrue, reason: key);
    }
  });
}
