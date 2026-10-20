// Overlay window size guard (PAR-027, shadow padding of the pill).
//
// The Dart pill reserves OverlayDesignSpec.shadowPadding on every side inside
// its native window so the painted shadow is not clipped. The native shells
// on macOS, Windows and Linux hard-code the window size instead of asking
// Dart. If one shell drifts from OverlayDesignSpec.windowSizeFor, the shadow
// or the pill is clipped on that platform only. The check reads the size
// literals in each shell source and compares them with the Dart spec.
//
// Static check: it proves the sizes match, not that the shadow renders.
import 'dart:io';

import 'package:flutter/painting.dart' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/overlay_design_spec.dart';

/// Size of one window per variant, read from a native source.
typedef _Dims = ({int w, int h});

_Dims _dimsFromMatch(RegExpMatch m) =>
    (w: int.parse(m.group(1)!), h: int.parse(m.group(2)!));

/// macOS: `switch sizeClass { case "compact": return NSSize(...) ... }`.
Map<OverlaySizeVariant, _Dims> _macos(String source) {
  RegExpMatch match(String key) {
    final m = RegExp(
      '$key:\\s*return NSSize\\(width: (\\d+), height: (\\d+)\\)',
    ).firstMatch(source);
    expect(m, isNotNull, reason: 'NSSize literal for "$key" not found');
    return m!;
  }

  return {
    OverlaySizeVariant.normal: _dimsFromMatch(
      RegExp(
        r'default:\s*return NSSize\(width: (\d+), height: (\d+)\)',
      ).firstMatch(source)!,
    ),
    OverlaySizeVariant.compact: _dimsFromMatch(match('"compact"')),
    OverlaySizeVariant.mini: _dimsFromMatch(match('"mini"')),
  };
}

/// Windows and Linux: `constexpr int <prefix>W = n;` and `<prefix>H = n;`.
Map<OverlaySizeVariant, _Dims> _constants(
  String source, {
  required String normal,
  required String compact,
  required String mini,
}) {
  _Dims pair(String prefix) {
    int value(String name) {
      final m = RegExp('$name = (\\d+);').firstMatch(source);
      expect(m, isNotNull, reason: '$name not found');
      return int.parse(m!.group(1)!);
    }

    return (w: value('${prefix}W'), h: value('${prefix}H'));
  }

  return {
    OverlaySizeVariant.normal: pair(normal),
    OverlaySizeVariant.compact: pair(compact),
    OverlaySizeVariant.mini: pair(mini),
  };
}

final _shells = <String, Map<OverlaySizeVariant, _Dims>>{
  'macos': _macos(
    File('macos/Runner/FloatingOverlayHost.swift').readAsStringSync(),
  ),
  'windows': _constants(
    File('windows/runner/floating_overlay_host.cpp').readAsStringSync(),
    normal: 'kNormal',
    compact: 'kCompact',
    mini: 'kMini',
  ),
  'linux': _constants(
    File('linux/runner/floating_overlay_window.h').readAsStringSync(),
    normal: 'kOverlayNormal',
    compact: 'kOverlayCompact',
    mini: 'kOverlayMini',
  ),
};

void main() {
  for (final variant in OverlaySizeVariant.values) {
    final Size spec = OverlayDesignSpec.windowSizeFor(variant);

    test('native shells use the Dart window size for ${variant.name}', () {
      for (final entry in _shells.entries) {
        final dims = entry.value[variant]!;
        expect(
          Size(dims.w.toDouble(), dims.h.toDouble()),
          spec,
          reason: '${entry.key} shell differs from OverlayDesignSpec',
        );
      }
    });
  }

  test('window size is the pill plus the shadow padding on each side', () {
    const pad = OverlayDesignSpec.shadowPadding;
    for (final variant in OverlaySizeVariant.values) {
      final pill = OverlayDesignSpec.sizeFor(variant);
      expect(
        OverlayDesignSpec.windowSizeFor(variant),
        Size(pill.width + 2 * pad, pill.height + 2 * pad),
      );
    }
  });
}
