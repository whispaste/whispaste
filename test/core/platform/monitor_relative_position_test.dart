/// Per-monitor memory of a window position (ticket, matrix 9.4).
library;

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/platform/monitor_relative_position.dart';

const _laptop = Rect.fromLTWH(0, 0, 1440, 900);
const _external = Rect.fromLTWH(1440, -200, 2560, 1440);
const _displays = [_laptop, _external];
const _size = Size(300, 80);

void main() {
  group('remember', () {
    test('stores the position relative to the monitor it sits on', () {
      final remembered = MonitorRelativePosition.remember(
        const {},
        const Offset(1640, 100),
        _size,
        _displays,
      );
      final key = MonitorRelativePosition.keyFor(_external);
      expect(remembered[key], const Offset(200, 300));
      expect(remembered, hasLength(1));
    });

    test('keeps the memory of other monitors', () {
      final first = MonitorRelativePosition.remember(
        const {},
        const Offset(100, 700),
        _size,
        _displays,
      );
      final second = MonitorRelativePosition.remember(
        first,
        const Offset(1640, 100),
        _size,
        _displays,
      );
      expect(second, hasLength(2));
      expect(
        second[MonitorRelativePosition.keyFor(_laptop)],
        const Offset(100, 700),
      );
    });
  });

  group('restore', () {
    test('returns the remembered position on the last-used monitor', () {
      final remembered = {
        MonitorRelativePosition.keyFor(_laptop): const Offset(100, 700),
        MonitorRelativePosition.keyFor(_external): const Offset(200, 300),
      };
      final restored = MonitorRelativePosition.restore(
        remembered: remembered,
        lastKey: MonitorRelativePosition.keyFor(_external),
        displays: _displays,
      );
      expect(restored, const Offset(1640, 100));
    });

    test('is null when the last-used monitor has no memory yet', () {
      final restored = MonitorRelativePosition.restore(
        remembered: {
          MonitorRelativePosition.keyFor(_laptop): const Offset(100, 700),
        },
        lastKey: MonitorRelativePosition.keyFor(_external),
        displays: _displays,
      );
      expect(restored, isNull);
    });

    test('is null when the last-used monitor is gone (caller falls back)', () {
      final restored = MonitorRelativePosition.restore(
        remembered: {
          MonitorRelativePosition.keyFor(_external): const Offset(200, 300),
        },
        lastKey: MonitorRelativePosition.keyFor(_external),
        displays: const [_laptop],
      );
      expect(restored, isNull);
    });

    test('a monitor with changed geometry is treated as unknown', () {
      const moved = Rect.fromLTWH(-2560, 0, 2560, 1440);
      final restored = MonitorRelativePosition.restore(
        remembered: {
          MonitorRelativePosition.keyFor(_external): const Offset(200, 300),
        },
        lastKey: MonitorRelativePosition.keyFor(_external),
        displays: [moved],
      );
      // The key is origin plus size, so a monitor with a different origin
      // is unknown and the caller falls back to the clamped position.
      expect(restored, isNull);
    });
  });

  group('restoreAt', () {
    test('uses the memory of the monitor the position lands on', () {
      final remembered = {
        MonitorRelativePosition.keyFor(_laptop): const Offset(100, 700),
      };
      // Clamped onto the laptop: its remembered spot wins over the clamp.
      final restored = MonitorRelativePosition.restoreAt(
        topLeft: const Offset(50, 600),
        size: _size,
        remembered: remembered,
        displays: _displays,
      );
      expect(restored, const Offset(100, 700));
    });

    test('is null without memory for that monitor', () {
      final restored = MonitorRelativePosition.restoreAt(
        topLeft: const Offset(1640, 100),
        size: _size,
        remembered: {
          MonitorRelativePosition.keyFor(_laptop): const Offset(100, 700),
        },
        displays: _displays,
      );
      expect(restored, isNull);
    });
  });

  group('encode / decode', () {
    test('round-trips through JSON', () {
      final map = {'a': const Offset(1, 2), 'b': const Offset(3.5, 4)};
      expect(
        MonitorRelativePosition.decode(MonitorRelativePosition.encode(map)),
        map,
      );
    });

    test('corrupt or empty input decodes to an empty memory', () {
      expect(MonitorRelativePosition.decode('{not json'), isEmpty);
      expect(MonitorRelativePosition.decode(''), isEmpty);
    });
  });
}
