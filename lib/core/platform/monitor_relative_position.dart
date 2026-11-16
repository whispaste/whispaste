/// Remembers an overlay position per monitor, relative to that monitor.
///
/// Positions are stored as offsets from the monitor's top-left corner, so a
/// remembered spot on an external display stays on it when the display comes
/// back after standby or a reconnect. A monitor is identified by its origin
/// and size (see [keyFor]); a monitor whose geometry changed is treated as
/// unknown, and the caller falls back to the clamped absolute position.
library;

import 'dart:convert';
import 'dart:ui';

abstract final class MonitorRelativePosition {
  /// Identifies a monitor by its origin and size, both rounded to whole
  /// pixels so that sub-pixel jitter from the platform does not split one
  /// monitor into two memories.
  static String keyFor(Rect display) =>
      '${display.left.round()},${display.top.round()},'
      '${display.width.round()}x${display.height.round()}';

  /// Returns [topLeft] of a window of [size] with its center on [displays],
  /// stored relative to the monitor it belongs to. Returns [memory] unchanged
  /// when no monitor contains the center.
  static Map<String, Offset> remember(
    Map<String, Offset> memory,
    Offset topLeft,
    Size size,
    List<Rect> displays,
  ) {
    final center = topLeft + Offset(size.width / 2, size.height / 2);
    final display = _displayContaining(center, displays);
    if (display == null) return memory;
    return {...memory, keyFor(display): topLeft - display.topLeft};
  }

  /// The absolute top-left for the remembered position on the monitor
  /// [lastKey], or null when that monitor is not connected or has no memory.
  static Offset? restore({
    required Map<String, Offset> remembered,
    required String? lastKey,
    required List<Rect> displays,
  }) {
    if (lastKey == null) return null;
    final offset = remembered[lastKey];
    if (offset == null) return null;
    for (final display in displays) {
      if (keyFor(display) == lastKey) return display.topLeft + offset;
    }
    return null;
  }

  /// The absolute top-left for the memory of the monitor that a window of
  /// [size] at [topLeft] lands on, or null when that monitor has no memory.
  static Offset? restoreAt({
    required Offset topLeft,
    required Size size,
    required Map<String, Offset> remembered,
    required List<Rect> displays,
  }) {
    final center = topLeft + Offset(size.width / 2, size.height / 2);
    final display = _displayContaining(center, displays);
    if (display == null) return null;
    final offset = remembered[keyFor(display)];
    if (offset == null) return null;
    return display.topLeft + offset;
  }

  /// JSON `{key: [dx, dy]}`. Corrupt input decodes to an empty memory.
  static Map<String, Offset> decode(String raw) {
    if (raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      final result = <String, Offset>{};
      for (final entry in decoded.entries) {
        final value = entry.value;
        if (entry.key is String &&
            value is List &&
            value.length == 2 &&
            value[0] is num &&
            value[1] is num) {
          result[entry.key as String] = Offset(
            (value[0] as num).toDouble(),
            (value[1] as num).toDouble(),
          );
        }
      }
      return result;
    } on FormatException {
      return const {};
    }
  }

  static String encode(Map<String, Offset> memory) => jsonEncode({
    for (final entry in memory.entries)
      entry.key: [entry.value.dx, entry.value.dy],
  });

  static Rect? _displayContaining(Offset point, List<Rect> displays) {
    for (final display in displays) {
      if (display.contains(point)) return display;
    }
    return null;
  }
}
